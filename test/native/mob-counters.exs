# Run from the generated Counter Mob project after ./build.sh --android.
# This deliberately leaves /counters/three uncached for the live demo.

qa_module_source = ~S"""
defmodule MobCountersNativeQA do
  def start(screen, view_id, controller) do
    caller = self()
    reference = make_ref()

    pid =
      spawn(fn ->
        :erlang.trace(screen, true, [:receive, {:tracer, self()}])
        send(caller, {:counter_trace_ready, reference})
        collect(screen, view_id, controller)
      end)

    receive do
      {:counter_trace_ready, ^reference} -> pid
    after
      5_000 -> raise "WebView trace did not start"
    end
  end

  def command(screen, view_id, code) do
    case Registry.lookup(MobWebView.Registry, {screen, view_id}) do
      [{view, _}] ->
        id = System.unique_integer([:positive, :monotonic])
        send(view, {:webview_command, %{id: id, action: "eval_js", code: code}})
        {:ok, id}

      [] ->
        {:error, :not_mounted}
    end
  end

  def stop(collector, screen) do
    reference = make_ref()
    send(collector, {:stop_trace, screen, self(), reference})

    receive do
      {:trace_stopped, ^reference} -> :ok
    after
      5_000 -> {:error, :trace_stop_timeout}
    end
  end

  defp collect(screen, view_id, controller) do
    receive do
      {:trace, ^screen, :receive, {:mob_webview, ^view_id, "eval_result", payload}} ->
        send(controller, {:counter_eval_result, payload})
        collect(screen, view_id, controller)

      {:stop_trace, ^screen, caller, reference} ->
        :erlang.trace(screen, false, [:all])
        send(caller, {:trace_stopped, reference})

      _ ->
        collect(screen, view_id, controller)
    end
  end
end
"""

Mix.Task.run("app.config")

if Mix.Project.config()[:app] != :counters_mobile do
  raise "Run this script from the generated :counters_mobile project"
end

serial = System.get_env("MOB_WEBVIEW_ANDROID_DEVICE") || raise("Set MOB_WEBVIEW_ANDROID_DEVICE")
package = MobDev.Config.bundle_id()

{resolved, 0} =
  System.cmd("adb", [
    "-s",
    serial,
    "shell",
    "cmd",
    "package",
    "resolve-activity",
    "--brief",
    package
  ])

component = resolved |> String.split("\n", trim: true) |> Enum.find(&String.contains?(&1, "/"))
if !component, do: raise("Android could not resolve the app's launch activity")

MobDev.Connector.start_epmd()
{_, 0} = System.cmd("adb", ["-s", serial, "reverse", "tcp:4369", "tcp:4369"])
System.cmd("adb", ["-s", serial, "reverse", "--remove", "tcp:47180"], stderr_to_stdout: true)
{_, 0} = System.cmd("adb", ["-s", serial, "shell", "am", "force-stop", package])
{_, 0} = System.cmd("adb", ["-s", serial, "shell", "run-as", package, "rm", "-rf", "app_webview"])
{_, 0} = System.cmd("adb", ["-s", serial, "shell", "am", "start", "-W", "-n", component])

prefix = Atom.to_string(Mix.Project.config()[:app]) <> "_android"
deadline = System.monotonic_time(:millisecond) + 20_000

await_dist = fn recur ->
  if !Enum.any?(MobDev.Tunnel.epmd_names(), fn {name, _} ->
       String.starts_with?(name, prefix)
     end) do
    if System.monotonic_time(:millisecond) >= deadline,
      do: raise("App did not register its development connection")

    Process.sleep(100)
    recur.(recur)
  end
end

await_dist.(await_dist)

{devices, _failed} =
  MobDev.Connector.connect_all(
    platforms: [:android],
    only: [serial],
    restart: false,
    name: String.to_atom("mob_counters_qa_#{System.pid()}@127.0.0.1")
  )

if length(devices) != 1, do: raise("Expected one connected Android app")
node = hd(devices).node

wait = fn label, predicate ->
  until = System.monotonic_time(:millisecond) + 30_000

  poll = fn poll ->
    case predicate.() do
      value when value not in [nil, false] ->
        value

      _ ->
        if System.monotonic_time(:millisecond) >= until, do: raise("Timeout: #{label}")
        Process.sleep(100)
        poll.(poll)
    end
  end

  poll.(poll)
end

screen_module = Module.concat(["CountersMobile", "HomeScreen"])
view_id = :site
wait.("generated Counter root", fn -> Mob.Test.screen(node) == screen_module end)

screen_pid =
  wait.("generated screen process", fn ->
    Enum.find_value(Mob.Test.screens(node), fn
      {_, ^screen_module, pid} -> pid
      _ -> nil
    end)
  end)

qa_module = Module.concat(["MobCountersNativeQA"])
[{^qa_module, binary}] = Code.compile_string(qa_module_source, "mob_counters_native_qa.ex")

{:module, ^qa_module} =
  :rpc.call(node, :code, :load_binary, [qa_module, ~c"mob_counters_native_qa.beam", binary])

collector = :rpc.call(node, qa_module, :start, [screen_pid, view_id, self()])

evaluate = fn code ->
  id =
    case :rpc.call(node, qa_module, :command, [screen_pid, view_id, code]) do
      {:ok, id} -> id
      other -> raise "Could not send WebView evaluation: #{inspect(other)}"
    end

  payload =
    wait.("JavaScript result", fn ->
      receive do
        {:counter_eval_result, %{"id" => ^id} = result} -> result
      after
        0 -> nil
      end
    end)

  payload["result"]
end

try do
  wait.("offline bundled Counter index", fn ->
    evaluate.("!!window.fogOfWar && !!document.querySelector('#page-title')")
  end)

  evaluate.(
    "window.fogOfWarStartup.then(result=>window.__counterBundle=result).catch(error=>window.__counterBundleError=error.message); true"
  )

  wait.("three-page import", fn -> evaluate.("!!window.__counterBundle?.complete") end)

  import = evaluate.("window.__counterBundle")

  if !(import["total"] == 3 && import["stored"] == 3),
    do: raise("Expected exactly three imported public pages, got #{inspect(import)}")

  evaluate.(
    "window.fogOfWar.cache.load(new URL('/counters/three',location.href)).then(record=>window.__threeCached=!!record); true"
  )

  wait.("uncached third counter check", fn -> evaluate.("window.__threeCached !== undefined") end)
  if evaluate.("window.__threeCached") != false, do: raise("Third counter was bundled")

  if !evaluate.("document.documentElement.classList.contains('fow-offline')"),
    do: raise("Counter did not start offline")

  evaluate.("document.querySelector('a[href=\"/counters/three\"]').click(); true")

  wait.("offline third counter denial", fn ->
    evaluate.(
      "location.pathname === '/' && window.fogOfWar.navigationEvents().some(e=>e.path==='/counters/three'&&e.outcome==='denied')"
    )
  end)

  evaluate.("document.querySelector('a[href=\"/counters/one\"]').click(); true")
  wait.("cached Counter one", fn -> evaluate.("location.pathname === '/counters/one'") end)

  if !evaluate.("document.querySelector('#counter-title')?.textContent === 'Counter one'"),
    do: raise("Cached Counter one did not render")

  evaluate.("document.querySelector('a.back-link[href=\"/\"]').click(); true")

  wait.("cached Counter index", fn ->
    evaluate.("location.pathname === '/' && !!document.querySelector('#page-title')")
  end)

  evaluate.("document.querySelector('a[href=\"/counters/two\"]').click(); true")
  wait.("cached Counter two", fn -> evaluate.("location.pathname === '/counters/two'") end)

  if !evaluate.("document.querySelector('#counter-title')?.textContent === 'Counter two'"),
    do: raise("Cached Counter two did not render")

  evaluate.(
    "window.__offlineCount=Number(document.querySelector('#count').textContent); document.querySelector('#increment-counter').click(); window.__offlineAfter=Number(document.querySelector('#count').textContent); true"
  )

  wait.("offline increment attempt", fn -> evaluate.("window.__offlineAfter !== undefined") end)

  if !evaluate.(
       "document.querySelector('#increment-counter').disabled && window.__offlineAfter === window.__offlineCount"
     ),
     do: raise("Offline increment changed the Counter")

  {_, 0} = System.cmd("adb", ["-s", serial, "reverse", "tcp:47180", "tcp:47180"])

  wait.("automatic LiveView recovery on Counter two", fn ->
    evaluate.("location.pathname === '/counters/two' && !!window.liveSocket?.main?.isConnected()")
  end)

  before = evaluate.("Number(document.querySelector('#count').textContent)")
  evaluate.("document.querySelector('#increment-counter').click(); true")

  wait.("live Counter increment", fn ->
    evaluate.("Number(document.querySelector('#count').textContent) === #{before + 1}")
  end)

  if evaluate.("location.pathname") != "/counters/two",
    do: raise("Recovery changed the selected route")

  IO.puts(
    "PASS: three bundled pages imported; unbundled third denied offline; cached navigation, blocked offline increment, and live recovery verified"
  )

  evaluate.("document.querySelector('a.back-link[href=\"/\"]').click(); true")

  wait.("return to live index", fn ->
    evaluate.("location.pathname === '/' && !!window.liveSocket?.main?.isConnected()")
  end)

  if !evaluate.("!window.fogOfWar.cache.find(new URL('/counters/three',location.href))"),
    do: raise("Demo's third counter unexpectedly cached")

  IO.puts("RETURN INDEX: #{evaluate.("location.pathname")}")
after
  :ok = :rpc.call(node, qa_module, :stop, [collector, screen_pid])
end
