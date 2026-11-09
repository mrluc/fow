# Counter

A small LiveView site with a counters index and three counter pages. The routed pages opt into Fog of War so their complete rendered state can be revisited offline. The developer panel is a separate sticky LiveView, available in development and on the hosted demo.

Start it from this directory with `source ../../../env.sh && mix phx.server`. Open `http://127.0.0.1:47180/`.

The app's content contains only the counter experience. Its shared layout includes `<FogOfWar.dev_tools socket={@socket} />` from the parent package, and `config/dev.exs` enables it with `config :fow, dev_tools: true`. The package owns the sticky LiveView, its hook, isolated styling, connection control and cache explorer. The example has no panel-specific JavaScript or CSS. The production demo enables it so visitors can try offline navigation.

Expand the launcher to inspect Cache or Help. The header pause/play control disconnects or reconnects the socket. Cache lists stored routes and navigation attempts; select a record to inspect its metadata and HTML. Snapshots use IndexedDB when available, with a localStorage fallback. Clear unused preserves routes open in cooperating Fog of War tabs and touches only FoW cache entries.

Each counter page has its own path and cached page state. Navigate from the index to a counter, increment it, visit another, then pause the connection from the developer panel and move among cached pages. Counter actions are unavailable while disconnected. Reconnect reloads the currently viewed route from the server.

The demo uses the package from the parent checkout via `{:fow, path: "../.."}`. Its normal asset import remains `import {FogOfWar, installFogOfWar} from "fow"` in `assets/js/app.js`.

## Android: commands used for the generated Counter app

The current client setup is already idiomatic FoW: the shared site layout wraps the whole routed page in `FogOfWar.region`, and `assets/js/app.js` installs the exported hook/coordinator. The package owns the DevTools. The public bundle contains `/`, `/counters/one` and `/counters/two`. `/counters/three` remains normally cacheable after an online visit, but is deliberately absent from the shipped bundle.

On this development Mac, start the website in one terminal and leave it running:

```sh
source /Users/mrluc/projects/vibes/elixir-client/env.sh
cd /Users/mrluc/projects/vibes/elixir-client/fow/examples/basic
mix assets.build
mix phx.server
```

In another terminal, these are the generation/build commands used for this run. `mobile-env.sh` is our local toolchain/cache helper, not a Mob requirement; an ordinary installation instead needs the toolchain checked by `mix mob.doctor`. `MIX_ARCHIVES` selects the Mob generator already installed in this workspace.

```sh
source /Users/mrluc/projects/vibes/elixir-client/mobile-env.sh
export MIX_ARCHIVES="$ELIXIR_CLIENT_ROOT/.cache/mix-archives"
cd /Users/mrluc/projects/vibes/elixir-client/fow/examples/basic

mix fow.bundle.prepare --env android-dev --platform android
mix fow.gen.mob --env android-dev --output .fow/apps/mob/android-dev
cd .fow/apps/mob/android-dev
mix deps.get

mix mob.emulators --list --android
mix mob.emulators --start --id Mob_API35_ARM64
adb -s emulator-5554 wait-for-device
adb -s emulator-5554 shell 'while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 1; done'
./build.sh --android
```

Once the emulator is booted, forward the website and explicitly launch the generated app:

```sh
adb -s emulator-5554 reverse tcp:47180 tcp:47180
adb -s emulator-5554 shell am start -W -n dev.fogofwar.counters/com.example.counters_mobile.MainActivity
```

The explicit launch targets the generated **Counters** app. The scaffold's Kotlin activity namespace differs from its application ID, so this avoids Mob's current launcher assumption. `./build.sh --android` runs dependency fetching, `mix mob.install`, then `mix mob.deploy --native --android`.

The first export/generation commands above refuse existing output. For a repeatable fresh run without deleting the working app or its caches, use a new run directory from the example directory:

```sh
COUNTER_RUN=".fow/android-runs/$(date +%Y%m%d-%H%M%S)"
mix fow.bundle.prepare --env android-dev --platform android --output "$COUNTER_RUN/bundle/android"
mix fow.gen.mob --env android-dev --bundle-dir "$COUNTER_RUN/bundle" --output "$COUNTER_RUN/app"
cd "$COUNTER_RUN/app"
./build.sh --android
```

For subsequent Elixir-only updates in an existing generated project, use `mix mob.deploy --android`; native code changes require `mix mob.deploy --native --android`. Changes to baked HTML/JS/CSS require preparing and packaging a new bundle, not just rebuilding the website.

From either generated project directory, run the native check using the source repository's script:

```sh
MOB_WEBVIEW_ANDROID_DEVICE=emulator-5554 mix run --no-start /Users/mrluc/projects/vibes/elixir-client/fow/test/native/mob-counters.exs
```

It clears only this development app's WebView data, removes website forwarding before startup, imports exactly three bundled routes, verifies that Three is unavailable offline, visits One and Two from cache, and checks that Increment is disabled. It restores forwarding, requires automatic recovery at Two, verifies a real server increment, then returns to the live index. It never visits Three online, so Three remains uncached for the demonstration. The generated HomeScreen has no test handlers; a temporary on-device observer reads its WebView events.

## Android top bar: native bounds, not website padding

The generated Counter and Frontier apps were compared on the same Android ARM64 emulator. Both report exactly the same native bounds on its 1080 × 2340 display:

| Region | Physical bounds |
| --- | --- |
| Android status/camera-cutout area | `[0,0]–[1080,136]` |
| WebView and its native holder | `[0,136]–[1080,2208]` |
| Android navigation-bar area | `[0,2208]–[1080,2340]` |

The generated Mob activity applies `safeDrawingPadding()` once at the root. Android reports a 136-pixel top camera-cutout/status-bar inset, and Mob reports the matching 49.45 dp inset at density 2.75. Its component tree has only a root column and the native WebView, with no header. There is no additional WebView or HTML top gap. The black area belongs to the host/system safe area; changing its appearance or drawing behind the camera cutout is a native host policy, not a Frontier CSS fix. Safe-area behavior is left intact.

Mob's `view_tree` reports the logical native-view node but no child frame in this build, and `element_frames` is empty for this screen. Android's hierarchy gives the actual pixel rectangles. To capture it while the app is visible:

```sh
adb -s emulator-5554 shell uiautomator dump /sdcard/counter-layout.xml
adb -s emulator-5554 pull /sdcard/counter-layout.xml /tmp/counter-layout.xml
adb -s emulator-5554 shell dumpsys window displays > /tmp/counter-window-insets.txt
```

The comparison artifacts from this run are in the repository's ignored `results/android-layout/` directory, including rectangle JSON for both apps and Mob's Counter tree/insets report.

## Fly.io

The public demo is at https://fow-counters.fly.dev. Deploy from the repository root with `bin/deploy example basic`. The Fly app needs a `SECRET_KEY_BASE` secret. The machine can stop while idle. The counters share an in-memory Agent, so a machine restart resets them.
