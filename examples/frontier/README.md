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

From the package root, `node test/native/frontier-smoke.cjs` tests the actual generated desktop app's terrain, logo loading, IndexedDB cache, offline movement, denied uncached movement, and Back navigation. It temporarily injects a test driver, then restores the source and rebuilds the ordinary app before returning.
