# Run from examples/wrappers/mob after deploying the native plugin and prepared Frontier bundle.
# Clears only this throwaway host's WebView data, not its deployed Elixir/runtime files.
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
  unless component, do: raise("Android could not resolve the app's launch activity")
  MobDev.Connector.start_epmd()
  {_, 0} = System.cmd("adb", ["-s", serial, "reverse", "tcp:4369", "tcp:4369"])
  {_, 0} = System.cmd("adb", ["-s", serial, "shell", "am", "force-stop", package])
  System.cmd("adb", ["-s", serial, "shell", "run-as", package, "rm", "-rf", "app_webview"])
  {_, 0} = System.cmd("adb", ["-s", serial, "shell", "am", "start", "-W", "-n", component])
  # Attach deliberately has a short timeout; wait for the real delayed Mob
  # distribution registration rather than racing its cold-start delay.
  prefix = Atom.to_string(Mix.Project.config()[:app]) <> "_android"
  deadline = System.monotonic_time(:millisecond) + 20_000

  await_dist = fn recur ->
    unless Enum.any?(MobDev.Tunnel.epmd_names(), fn {name, _} ->
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

unless length(devices) == 1 do
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

wait.("Frontier root", fn -> Mob.Test.screen(node) == CountersMobile.FrontierScreen end)

evaluate = fn code ->
  ref = make_ref()
  :ok = Mob.Test.send_message(node, {:qa_eval, self(), ref, code})

  id =
    receive do
      {:qa_eval, ^ref, {:ok, id}} -> id
    after
      5_000 -> raise "No eval acknowledgment"
    end

  payload =
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

  payload["result"]
end

wait.("packaged map and IndexedDB import", fn ->
  evaluate.("!!window.fogOfWar && !!document.querySelector('#map-scene')")
end)

IO.inspect(
  evaluate.(
    "({url:location.href,origin:location.origin,offline:document.documentElement.classList.contains('fow-offline'),images:[...document.images].map(i=>({src:i.src,loaded:i.complete&&i.naturalWidth>0})),canvas:!!document.querySelector('canvas.pixel-fog')})"
  ), label: "COLD START")

evaluate.(
  "window.fogOfWarStartup.then(result=>window.__bundleResult=result).catch(error=>window.__bundleError=error.message); true"
)

wait.("batch import", fn -> evaluate.("!!window.__bundleResult?.complete") end)
IO.inspect(evaluate.("window.__bundleResult || window.__bundleError"), label: "IMPORT")

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

unless assets["ok"] && assets["count"] == 5, do: raise("Packaged art failed: #{inspect(assets)}")

wait.("pixel fog paint", fn ->
  evaluate.(
    "[...document.querySelector('canvas.pixel-fog').getContext('2d').getImageData(0,0,innerWidth,innerHeight).data].some((v,i)=>i%4===3&&v>0)"
  )
end)

evaluate.("document.querySelector('a[href=\"/lat/0/lon/1\"]').click(); true")
wait.("cached navigation", fn -> evaluate.("location.pathname === '/lat/0/lon/1'") end)

IO.puts(
  "PASS: fresh offline Frontier, packaged artwork, compressed IndexedDB import and cached navigation"
)

{_, 0} = System.cmd("adb", ["-s", hd(serials), "reverse", "tcp:47190", "tcp:47190"])

wait.("automatic online recovery", fn ->
  evaluate.("!!document.querySelector('[data-phx-main]')?.classList.contains('phx-connected')")
end)

unless evaluate.("location.pathname") == "/lat/0/lon/1", do: raise("Recovery changed the route")
evaluate.("document.querySelector('a[href=\"/lat/0/lon/2\"]').click(); true")

wait.("live navigation", fn ->
  evaluate.(
    "location.pathname === '/lat/0/lon/2' && !!document.querySelector('[data-phx-main]')?.classList.contains('phx-connected')"
  )
end)

IO.puts("PASS: automatic reconnect preserves selected route, followed by live server navigation")
