# Run from a generated Frontier Mob project after ./build.sh --android.
# Clears only this throwaway host's WebView data, not its deployed Elixir/runtime files.

# The generated screen intentionally has no QA handlers or event assigns. Trace
# only its incoming WebView eval results from a test-only process on the device.
qa_module_source = ~S"""
defmodule MobFrontierNativeQA do
  def start(screen, view_id, controller) do
    caller = self()
    reference = make_ref()
    pid = spawn(fn ->
      :erlang.trace(screen, true, [:receive, {:tracer, self()}])
      send(caller, {:trace_ready, reference})
      collect(screen, view_id, controller)
    end)
    receive do
      {:trace_ready, ^reference} -> pid
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
        send(controller, {:mob_frontier_eval_result, payload})
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

serials =
  case System.get_env("MOB_WEBVIEW_ANDROID_DEVICE") do
    nil -> []
    serial -> [serial]
  end

# Mob's current restart helper assumes package/.MainActivity. The generated
# wrapper has a customized applicationId and a different Kotlin namespace,
# so ask Android for the actual launch component instead of guessing its name.
if serials != [] do
  serial = hd(serials)
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
  System.cmd("adb", ["-s", serial, "reverse", "--remove", "tcp:47190"])
  {_, 0} = System.cmd("adb", ["-s", serial, "shell", "am", "force-stop", package])

  {_, 0} =
    System.cmd("adb", ["-s", serial, "shell", "run-as", package, "rm", "-rf", "app_webview"])

  {_, 0} = System.cmd("adb", ["-s", serial, "shell", "am", "start", "-W", "-n", component])
  # Attach deliberately has a short timeout; wait for the real delayed Mob
  # distribution registration rather than racing its cold-start delay.
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
end

{devices, _failed} =
  MobDev.Connector.connect_all(
    platforms: [:android],
    only: serials,
    restart: false,
    name: String.to_atom("mob_webview_qa_#{System.pid()}@127.0.0.1")
  )

if length(devices) != 1 do
  raise "Expected one connected Android app; set MOB_WEBVIEW_ANDROID_DEVICE to select its serial"
end

node = hd(devices).node

wait = fn label, predicate ->
  deadline = System.monotonic_time(:millisecond) + 30_000

  poll = fn poll ->
    case predicate.() do
      value when value not in [nil, false] ->
        value

      _ ->
        if System.monotonic_time(:millisecond) >= deadline, do: raise("Timeout: #{label}")
        Process.sleep(100)
        poll.(poll)
    end
  end

  poll.(poll)
end

{screen_module, view_id} =
  case Mix.Project.config()[:app] do
    :frontier_mobile -> {Module.concat(["FrontierMobile", "HomeScreen"]), :site}
    app -> raise "Unsupported Mob test host #{inspect(app)}"
  end

wait.("Frontier root", fn -> Mob.Test.screen(node) == screen_module end)

screen_pid =
  wait.("Frontier screen process", fn ->
    Enum.find_value(Mob.Test.screens(node), fn
      {_, ^screen_module, pid} -> pid
      _ -> nil
    end)
  end)

generated_screen? = Mix.Project.config()[:app] == :frontier_mobile

collector =
  if generated_screen? do
    module = Module.concat(["MobFrontierNativeQA"])
    [{^module, binary}] = Code.compile_string(qa_module_source, "mob_frontier_native_qa.ex")

    {:module, ^module} =
      :rpc.call(node, :code, :load_binary, [module, ~c"mob_frontier_native_qa.beam", binary])

    :rpc.call(node, module, :start, [screen_pid, view_id, self()])
  end

evaluate = fn code ->
  id =
    if generated_screen? do
      case :rpc.call(node, Module.concat(["MobFrontierNativeQA"]), :command, [
             screen_pid,
             view_id,
             code
           ]) do
        {:ok, id} -> id
        other -> raise "Could not send WebView evaluation: #{inspect(other)}"
      end
    else
      ref = make_ref()
      :ok = Mob.Test.send_message(node, {:qa_eval, self(), ref, code})

      receive do
        {:qa_eval, ^ref, {:ok, id}} -> id
      after
        5_000 -> raise "No eval acknowledgment"
      end
    end

  payload =
    if generated_screen? do
      wait.("JavaScript result", fn ->
        receive do
          {:mob_frontier_eval_result, %{"id" => ^id} = payload} -> payload
        after
          0 -> nil
        end
      end)
    else
      wait.("JavaScript result", fn ->
        case Mob.Test.assigns(node) do
          %{events: events} ->
            Enum.find_value(events, fn {event, payload} ->
              if event == "eval_result" && payload["id"] == id, do: payload
            end)

          _ ->
            nil
        end
      end)
    end

  payload["result"]
end

try do
  wait.("packaged map and IndexedDB import", fn ->
    evaluate.("!!window.fogOfWar && !!document.querySelector('#map-scene')")
  end)

  if !evaluate.("document.documentElement.classList.contains('fow-offline') && !window.liveSocket.isConnected()"),
    do: raise("Cold launch unexpectedly connected to the website")

  IO.inspect(
    evaluate.(
      "({url:location.href,origin:location.origin,offline:document.documentElement.classList.contains('fow-offline'),images:[...document.images].map(i=>({src:i.src,loaded:i.complete&&i.naturalWidth>0})),canvas:!!document.querySelector('canvas.pixel-fog')})"
    ),
    label: "COLD START"
  )

  evaluate.(
    "window.fogOfWarStartup.then(result=>window.__bundleResult=result).catch(error=>window.__bundleError=error.message); true"
  )

  wait.("batch import", fn -> evaluate.("!!window.__bundleResult?.complete") end)
  result = evaluate.("window.__bundleResult || window.__bundleError")
  IO.inspect(result, label: "IMPORT")

  if !match?(%{"complete" => true, "total" => 4, "stored" => 4}, result),
    do: raise("Fresh IndexedDB did not import all four bundled routes")

  evaluate.(~S"""
  window.__assetQA = null;
  Promise.all(['/images/fog-of-war-logo.png','/images/terrain.png','/images/pine.png','/images/scout-idle.png','/images/scout-walk.png'].map(path => new Promise((resolve,reject)=>{
    const image=new Image(); image.crossOrigin='anonymous';
    image.onload=()=>{try{const canvas=document.createElement('canvas');canvas.width=canvas.height=4;
      const ctx=canvas.getContext('2d');ctx.drawImage(image,0,0,4,4);ctx.getImageData(0,0,4,4);resolve(path)}catch(e){reject(e)}};
    image.onerror=()=>reject(new Error(path));image.src=path;
  }))).then(paths=>window.__assetQA={ok:true,count:paths.length},error=>window.__assetQA={ok:false,error:error.message}); true;
  """)

  assets =
    wait.("decoded, canvas-readable packaged sprites", fn -> evaluate.("window.__assetQA") end)

  if !(assets["ok"] && assets["count"] == 5),
    do: raise("Packaged art failed: #{inspect(assets)}")

  wait.("pixel fog paint", fn ->
    evaluate.(
      "[...document.querySelector('canvas.pixel-fog').getContext('2d').getImageData(0,0,innerWidth,innerHeight).data].some((v,i)=>i%4===3&&v>0)"
    )
  end)

  evaluate.("document.querySelector('a[href=\"/lat/0/lon/1\"]').click(); true")
  wait.("cached navigation", fn -> evaluate.("location.pathname === '/lat/0/lon/1'") end)

  IO.puts("PASS: fresh offline Frontier, packaged artwork, compressed IndexedDB import and cached navigation")

  {_, 0} = System.cmd("adb", ["-s", hd(serials), "reverse", "tcp:47190", "tcp:47190"])

  wait.("automatic online recovery", fn ->
    evaluate.("!!document.querySelector('[data-phx-main]')?.classList.contains('phx-connected')")
  end)

  if evaluate.("location.pathname") != "/lat/0/lon/1", do: raise("Recovery changed the route")
  evaluate.("document.querySelector('a[href=\"/lat/0/lon/2\"]').click(); true")

  wait.("live navigation", fn ->
    evaluate.(
      "location.pathname === '/lat/0/lon/2' && !!document.querySelector('[data-phx-main]')?.classList.contains('phx-connected')"
    )
  end)

  IO.puts("PASS: automatic reconnect preserves selected route, followed by live server navigation")
after
  if generated_screen? && is_pid(collector) do
    :ok = :rpc.call(node, Module.concat(["MobFrontierNativeQA"]), :stop, [collector, screen_pid])
  end
end
