# Frontier: The Green March

A separate Phoenix LiveView example of Fog of War navigation. A 4×4 map starts at `/lat/0/lon/0`. Each location contains a 3×3 patch of procedural grass-and-dirt tiles. Travel links lead only to the eight immediately surrounding coordinates (three at the starting corner). Coordinates outside 0–3 redirect to camp.

```sh
cd examples/frontier
mix deps.get
mix assets.setup
mix assets.build
mix phx.server
```

Open http://127.0.0.1:47190/lat/0/lon/0. The three neighboring public pages are preloaded from real server renders into the Fog of War cache after the initial page mounts. This is online preloading, not a bundled cold-offline first installation. Saving those neighboring pages does not change the current tab's route protection. A completed preload is marked in `frontier:seed:v2`; remove that key to repeat it.

Open the floating developer tools and pause the connection. Neighboring cached locations remain navigable. Other locations are black until visited; known ground is dimmed under a grey checkerboard facing the camera. The map fills the viewport: no heading, journal, legend or coordinate labels; the Fog of War logo floats in the upper-left corner. Click an adjacent diamond to move; each diamond remains a keyboard-accessible link with a descriptive accessible name. The floating developer tools are the only surrounding UI. No database or Counter app code is used.

## Terrain and artwork

`node scripts/generate-terrain.cjs` regenerates a deterministic, continuous 768×768 grass-and-dirt texture and the coordinate CSS. Four octaves of seeded value noise, finer grain, and irregular footpaths produce 144 constituent tiles. Each sector displays nine of them. The script requires only Node's standard library; PNG encoding is included.

The emblem, pine, standing scout, and walking scout are original generated PNGs with real transparency. See [ASSETS.md](ASSETS.md) for filenames, generation prompts and provenance. No Kenney sprites are used in this version.

## Walking transitions

`assets/js/map-transitions.js` connects LiveView's document patch callback and Fog of War's cached navigation to the same View Transition API. The scout has a named view-transition element; its before/after positions interpolate across the map while CSS alternates the idle and walking snapshots. The actual scout returns to its idle pose when the transition finishes. Terrain and tile targets remain still. Reduced-motion preferences and browsers without the API apply navigation immediately. This is a simple two-pose walk, not a full directional animation set.

`test/map_test.exs` checks routes, adjacency and tile counts. The package's `test/browser/frontier.spec.cjs` checks initial preloading, transitions, whole-tile navigation, fog layers, absence of page chrome, missing destinations, and immediate Back after cached moves. Neither the tests nor the app sleep to make history work.


## Responsive map and pixel fog

`assets/js/map-viewport.js` fits the map continuously to the viewport and centers its visual bounds. It keeps fog in a fixed, unscaled canvas above terrain and trees. Terrain diamonds and the pine PNG's alpha form a mask; thresholding that mask produces hard edges. The checkerboard is aligned to the viewport, with 1 CSS-pixel cells, nearest-neighbor display, and no intermediate fog alpha values. Scaling the map does not scale the checkerboard. The same compositor observes live patches, cache-state changes and cached navigation; it does not depend on mounting hooks on saved HTML.

## macOS app: Frontier

`.fow.json` names the app **Frontier**, uses the same Fog of War logo as its launcher icon, and selects the four initial public coordinates. `elixirkit.startup: "live"` opens the map directly, without an intermediate public-shell page or an “Open live site” button. This development build connects to `http://127.0.0.1:47190`; keep the Frontier Phoenix server running. This mode needs the server on launch. Cached navigation works after loading, but seamless bundled-first offline launch is a separate startup mode still to be implemented.

With the server running, from this example directory:

```sh
mix fow.export
mix fow.gen.elixirkit
cd .fow/apps/elixirkit/dev
./build.sh
```

For a single-command rebuild and local installation, run `mix fow.desktop --force` from this example directory. It refreshes the public export, replaces the generated project, builds and installs `Frontier.app` into `~/Applications`, then registers it for Spotlight. This discards changes inside the generated project; the example source and artwork remain untouched. Separate generation supports `--force`; standalone `mix fow.export` still requires a fresh export directory. Build uses the normal desktop toolchain; the repository's `elixir-client/env.sh` selects the shared native compilation cache on this development machine.

The resulting `Frontier.app` is under `$CARGO_TARGET_DIR/release/bundle/macos/` (or the generated project's `src-tauri/target/release/bundle/macos/` without that environment variable). Copy it into `~/Applications` to launch it from Spotlight. It is locally signed for development, not notarized for distribution.

From the package root, `node test/native/frontier-outage.cjs` tests a freshly generated desktop app, stops Phoenix, checks offline navigation and history, and restarts Phoenix to verify live recovery.


## Android app generated from Frontier

The `android-dev` manifest environment selects Android only. With Frontier's Phoenix server running, generate and build from this example directory:

```sh
mix fow.bundle.prepare --env android-dev --platform android
mix fow.gen.mob --env android-dev --output .fow/apps/mob/android-dev
cd .fow/apps/mob/android-dev
./build.sh --android
```

The generated app is **Frontier**, with application ID `dev.fogofwar.frontier`. It fetches the pinned WebView package from Git, includes the public startup document, compressed routes and artwork, and has no wrapper toolbar. Its HomeScreen contains no test hooks. The repository is private for now, so dependency fetching requires GitHub SSH access. The build uses the normal Mob toolchain and existing runtime caches; it does not use the older Counter test host.

From the generated project directory, this native test clears that development app's WebView data, opens it without website forwarding, checks the bundled routes and canvas-readable artwork, then restores forwarding and requires recovery on the chosen route followed by live navigation:

```sh
MOB_WEBVIEW_ANDROID_DEVICE=emulator-5554 mix run --no-start ../../../../../../test/native/mob-frontier.exs
```

Android ARM64 emulator execution passed from this generated project. The debug build also compiled ARM32 and x86_64 libraries; those architectures were not run. The generator emits dense library copies on macOS to avoid sparse-copy corruption of NDK output, and refuses an unfamiliar upstream copy layout. No generated source files need manual repair.

Bundle preparation refuses an existing destination. For another export, use a fresh `--output` directory, then pass its parent as `--bundle-dir` to generation. Generator `--force` replaces the entire generated project, including its local dependencies and build outputs; keep any custom changes elsewhere.

## Development game inspector

Open `/dev/game` on the running Frontier server. The inspector reads the default `FogOfWarFrontier.Game` process. Select a square or click a player in the list to follow their authoritative position and inspect their record. The map and records update every game tick.

The route is compiled only with `:dev_routes` enabled, as in the development and test configurations. The multiplayer player view consumes this same authoritative state. Rejected moves return it to the accepted coordinate; the legacy single-player route still runs independently.

The engine is a pure `Game.State` value with `dispatch/2` and `step/2`. Named Game processes can run with `automatic: false` for deterministic tests. `Game.step(server, actions)` advances one tick. Tests in `test/game_state_test.exs` and `test/game_inspector_test.exs` cover rules and two LiveViews observing the same stepped game.

## Streamed multiplayer view

Open `http://127.0.0.1:47190/multi/lat/0/lon/0`. Both map routes use the same terrain, player sprite, camera, HUD, connection controls and offline navigation.

The multiplayer route streams ground tiles, tree groups and other entities. It includes other players and the monster only on the square currently being viewed. Entity IDs and order are stable. CSS `nth-child` rules define all display offsets. The current player's sprite keeps its existing placement and walking transitions. Other entities animate on entry, slot changes and departure.

Connected multiplayer views read the game's ETS snapshot on tick notifications. Each retains its own player record and a small comparison map for visible entities. Server health and move charge reconcile the HUD; rejected moves and movement from another tab correct the route through LiveView patches. Offline navigation and HUD prediction remain client-side, then reconcile on reconnect. Returning to a backgrounded tab requests a fresh player record. Entity streams insert changed records and delete departures without resetting the entire list.

Desktop and mobile builds now start on the multiplayer route by default. The previous single-player bundle is available with `--env single-dev`. The existing `multi-dev` environment remains a compatible alias:

```sh
mix fow.desktop --env multi-dev --force
```

The environment explicitly preloads the four multiplayer corner routes. It uses the same Frontier app name and installation destination.


Multiplayer deaths show a desaturated, translucent scout and a five-second respawn countdown. Lives begin at three and can go negative. A respawn clears remembered multiplayer routes before moving to the server-selected spawn. The monster repeats its explosion/flat/recover/idle cycle when a living player shares its square; it resumes walking after the square is unoccupied. Each explosion deals 70 HP to every living player on its square, once per three-second decision. Player attack controls are not implemented yet.


Game checkpoints live in ETS owned by the separately supervised `Game.Cache` process. A Game process crash preserves the match and connected view registrations. Restarting the entire application still starts fresh. The inspector's **Reset game** button deliberately clears exploration and respawns all players with full health and three lives; connected clients clear their remembered multiplayer routes before accepting their new position.


## Fly deployment

Frontier runs at https://fow.fly.dev. From the FoW repository root, using a current Fly CLI:

```sh
fly deploy . --config examples/frontier/fly.toml --remote-only --ha=false
fly status --app fow
fly logs --app fow
```

The repository root is the build context because Frontier uses FoW as a local path dependency. The Dockerfile builds the JavaScript, digests static assets, and produces an Elixir release. `SECRET_KEY_BASE` is stored as a Fly secret; `PHX_HOST` is set in `fly.toml`. The public `/` entry opens multiplayer. Development routes, including the game inspector, are disabled in production.

Keep one Machine running: each instance currently owns an independent in-memory game. Automatic stopping is disabled so inactivity does not stop the game. A deploy or full Machine restart starts a fresh game; no database or volume is used. This initial deployment is manual; a GitHub `frontier` branch deployment and downloadable desktop release are separate follow-up steps.

To build and install the desktop app against the deployed site, from `examples/frontier`:

```sh
mix fow.desktop --env prod --force
```

The `prod` environment in `.fow.json` sets `web.origin` to `https://fow.fly.dev` and inherits the multiplayer startup route and four public preload routes. Captured bundles and generated projects are separated by environment. This command fetches from the deployed site; it does not require `MIX_ENV=prod` locally.


## Pausing and protecting the inspector

Open `/dev/game` locally. **Pause game** freezes automatic game time, health, monster decisions, respawns and movement/attacks. Connections can still attach or detach. **Step 100 ms** advances one tick while remaining paused; **Resume game** continues from that tick without catching up elapsed wall time. Pause is shared by every player and inspector, and survives a Game process restart. Reset preserves the pause setting.

The inspector uses the actual terrain, tree and entity sprites, showing all squares without exploration limits. Click a scout or the monster to inspect it, or click a square to inspect its contents. Pausing also freezes entity sprite animations and connected player HUD prediction.

Production keeps `/dev/game` hidden (404) by default. To opt into password protection on Fly, set runtime secrets after deploying this version:

```sh
fly secrets set --app fow \
  FRONTIER_INSPECTOR_ENABLED=true \
  FRONTIER_INSPECTOR_USERNAME=admin \
  FRONTIER_INSPECTOR_PASSWORD='choose-a-password'
```

Visit `https://fow.fly.dev/dev/game` and enter those credentials in the browser prompt. HTTP Basic Auth protects the initial request; a signed-session proof is checked again on LiveView mount in its separate `live_session`. Missing/wrong credentials return 401. An enabled production inspector without a password still returns 404. Changing the password invalidates old mount proofs. Local development remains open unless a password is configured.


Frontier explicitly uses `<FogOfWar.dev_tools enabled={true} ... />` so the public demo includes the tools in production. Other applications can set `enabled={@user.can_debug}`; an explicit boolean overrides application configuration.

The game inspector lists player LiveView process memory and mailbox length from one-second PubSub samples. It totals currently reported views, counts separate tabs separately, and drops reports at three seconds old (swept once per second). Reporting continues while the game is paused. These are allocated process bytes from `Process.info/2`, without forced garbage collection; shared reference-counted binary storage, socket processes and ETS are not included.
