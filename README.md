# Fog of War for Phoenix LiveView

Fog of War gives selected LiveView pages a last-known, read-only view when the server is unavailable. Add the `FogOfWar` hook to a page’s top-level rendered element. Fog of War saves that element after server updates and restores it when someone navigates to the cached route offline. Online navigation and events continue to use LiveView.

This package is experimental and has not been published to Hex. Its Mix application name is `:fow`. The public Elixir module is `FogOfWar`; `FoW` is a short module alias. This prototype is tested with LiveView 1.2.13.

## Installation

Until a Hex release is available, check out the Fog of War package alongside your application and add it to the dependencies in your application’s `mix.exs`:

```elixir
defp deps do
  [
    {:fow, path: "../fow"},
    # Your existing dependencies...
  ]
end
```

Run `mix deps.get`. After publication, the dependency will be `{:fow, "~> 0.1"}` instead. Do not use that Hex dependency until a release exists.

In `assets/js/app.js`, import the hook and install it before connecting your existing LiveSocket:

```javascript
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {FogOfWar, installFogOfWar} from "fow"

const csrfToken = document.querySelector("meta[name='csrf-token']").content
const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {FogOfWar}, // Keep your other hooks here too.
})

installFogOfWar(liveSocket)
liveSocket.connect()
window.liveSocket = liveSocket
```

Keep the rest of your application’s imports, hooks and LiveSocket options; add the package to that existing setup rather than creating a second socket.

A normal Hex installation places the package in `deps/fow`. Phoenix’s default esbuild configuration already searches `deps`, so `from "fow"` resolves the JavaScript shipped in the Hex package. No separate npm install, vendored JavaScript or esbuild alias is needed. This follows the hook-import pattern documented by [LiveSelect](https://live-select.hexdocs.pm/readme.html#javascript-hooks); [esbuild’s Mix wrapper](https://esbuild.hexdocs.pm/Esbuild.html#module-profiles) documents the dependency search path.

Local path dependencies live outside `deps`. For a checkout alongside your application, add `Path.expand("../..", __DIR__)` to the existing `NODE_PATH` list in your application’s `config/config.exs`; this is the directory containing the `fow` checkout. The import in `app.js` stays the same. The nested runnable example configures its own search directory in its `config/config.exs`.

## Opt in a whole routed page

Use one `FogOfWar` hook per participating route, on the outermost element containing everything that route must show offline. Include its navigation links and page content. Keep persistent application controls outside the routed content if they must remain available when Fog of War replaces the page.

For example, add two routes to the browser scope in `lib/my_app_web/router.ex`:

```elixir
scope "/", MyAppWeb do
  pipe_through :browser
  live "/counter", CounterLive
  live "/notes", NotesLive
end
```

In `lib/my_app_web/live/counter_live.ex`:

```elixir
defmodule MyAppWeb.CounterLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket), do: {:ok, assign(socket, count: 0)}

  def handle_event("increment", _params, socket),
    do: {:noreply, update(socket, :count, &(&1 + 1))}

  def render(assigns) do
    ~H"""
    <section id="counter-page" phx-hook="FogOfWar" data-fog-of-war-path="/counter">
      <nav>
        <.link navigate={~p"/counter"}>Counter</.link>
        <.link navigate={~p"/notes"}>Notes</.link>
      </nav>
      <h1>Counter</h1>
      <output>{@count}</output>
      <button phx-click="increment">Increment counter</button>
    </section>
    """
  end
end
```

In `lib/my_app_web/live/notes_live.ex`:

```elixir
defmodule MyAppWeb.NotesLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, note: "This is the last note received from the server.")}
  end

  def render(assigns) do
    ~H"""
    <section id="notes-page" phx-hook="FogOfWar" data-fog-of-war-path="/notes">
      <nav>
        <.link navigate={~p"/counter"}>Counter</.link>
        <.link navigate={~p"/notes"}>Notes</.link>
      </nav>
      <h1>Notes</h1>
      <p>{@note}</p>
    </section>
    """
  end
end
```

Visit both pages while connected. Once disconnected, their links and browser Back/Forward can show their saved content. Server actions are disabled and are never queued for replay. Reconnecting after offline navigation fetches the currently displayed route from the server.

**The hook saves only its element and descendants.** Placing it on an inner paragraph would save only that paragraph; navigating back offline would not reconstruct the surrounding LiveView. Fog of War currently restores one saved element for a route, not a composition of separately cached fragments. Put the hook above any routed layout or other content that must be restored as part of that page.

Fog of War warns in the console when the hooked element is not a direct child of the main LiveView container. This catches obvious nested placement; layouts can also trigger the warning. It is a structural check, not proof that the element includes every part of the intended page. Keep the full page inside the hooked element and verify the rendered result with offline navigation.

### Optional markup helper

The hook above is the primary interface. If you prefer an Elixir markup helper, replace the outer `<section>` with `FogOfWar.region`; it emits the same `FogOfWar` hook and route attribute:

```heex
<FogOfWar.region id="counter-page" path="/counter">
  <%!-- The complete routed page: navigation, content and actions. --%>
</FogOfWar.region>
```

`FoW.region` is an equivalent spelling. The helper does not start or wrap a LiveView process and adds no extra offline capability. It belongs inside the LiveView’s render, surrounding its complete routed content.

### Why the path is explicit

`data-fog-of-war-path` identifies the route this page represents. The current implementation requires it rather than inferring the key from the address bar during a mount: live navigation can mount content before the browser URL is committed. Automatic route identity could be added at a committed navigation event, but that behavior is not implemented. Current cache matching supports fixed same-origin paths without query strings.

## Storage and account policy

Snapshots are stored in this browser’s IndexedDB, with compressed HTML kept as binary. Fog of War falls back to localStorage if its IndexedDB write/read probe fails; if both are blocked, the cache lasts only for the current document. Logged-in content can be cached when that is appropriate for the application; this does not publish it or put it in a public preload bundle. The application decides which pages should remain on the device and which must remain online-only.

Fog of War does not encrypt snapshots, partition them by account, or clear them on logout. Account scoping, invalidation, expiration and logout cleanup need to be designed before using this prototype for account-specific production data. The current `fog-of-war:page:` storage prefix is a historical namespace, not an access-control setting or a restriction to public content.

## Other asset builders

With npm-based builders, add Fog of War alongside the other Phoenix file dependencies in `assets/package.json`:

```json
{
  "dependencies": {
    "fow": "file:../deps/fow"
  }
}
```

Run `npm install --prefix assets`, preserving your other dependencies. For a local checkout rather than a Hex dependency, point the `file:` dependency at that checkout instead. The same `from "fow"` import and hook registration apply. This is the optional npm-based setup, not an additional step for Phoenix’s default esbuild setup.

## Developer tools

Include the package's sticky developer LiveView outside the region you cache, for example in the shared LiveView layout:

```heex
<FogOfWar.region id="saved-page" path={@path}>
  <!-- The complete routed page. -->
</FogOfWar.region>
<FogOfWar.dev_tools socket={@socket} />
```

In `config/config.exs`, choose when it is available:

```elixir
config :fow, dev_tools: config_env() == :dev
```

The default is disabled. A particular call can override this with `enabled={true}` or `enabled={false}`. `installFogOfWar(liveSocket)` installs the tool's hook before `liveSocket.connect()`; no additional hook imports, example-specific JavaScript, CSS imports or document click listeners are needed. The package ships the LiveView, markup, styles and client code. Styles live in a ShadowRoot so the host application's styles do not alter the controls.

Use `scale={0.9}` on `<FogOfWar.dev_tools>` to shrink its text, controls, and spacing (default: `1.0`). This sets `--fog-of-war-dev-tools-scale` on the tool host; panel docking and resize dimensions stay in viewport pixels. For example: `<FogOfWar.dev_tools socket={@socket} scale={0.9} />`.

Use `<FogOfWar.dev_tools socket={@socket} semi_transparent={true} />` to start the panel semi-transparent (default: `false`). The overlapping-squares icon beside the tabs toggles this preference for the current tab, including across navigation and reloads. The pause/play button disconnects or reconnects the socket.

The small launcher expands into a floating, dockable toolbar. Its header always shows the Live / Disconnected status and a pause/play control. **Cache** combines saved pages with in-memory navigation attempts, live arrivals, cached visits and denials. Cache/Nav checkboxes filter the rows; the default order is newest first and every column is sortable. Vsn means the stored record format; the renderer compatibility tag remains in the selected page's details. Select a saved page to read its decoded HTML and metadata, or a navigation event for its outcome and reason. The footer names the storage backend. IndexedDB sizes count encoded payload and metadata bytes, excluding database overhead; the localStorage fallback estimates UTF-16 keys and values.

**Clear unused** removes only Fog of War page entries for routes that are not open in cooperating Fog of War tabs on this origin. Every initialized tab holds a shared Web Lock for its current route, including while reading cached pages. Registration and clearing share a maintenance lock; this uses live browser ownership rather than expiring timestamps. Closing the document releases its locks. Unreadable records are preserved because their route cannot be verified. If Web Locks is unavailable, inspection still works and clearing is disabled. Older clients and tabs that do not initialize Fog of War cannot advertise their open routes; this is not a browser-wide tab inventory.

The sticky LiveView preserves the tool across ordinary LiveView navigation. When offline browsing retires the original LiveViews, the coordinator explicitly takes ownership of the tool's DOM and scoped listeners. Its tabs, inspector, clear action and reconnect control continue working; reconnect loads the currently viewed route afresh. A full document navigation creates a new tool instance.

## Run the example

From the package checkout:

```bash
cd examples/basic
mix setup
mix phx.server
```

Open [the basic example](http://127.0.0.1:47180/). The site shows a counters index and separate counter pages; its content contains no library-specific controls. In development, the package’s compact floating toolbar provides Cache and Help tabs, with connection controls always in its header. Expand it to disconnect/reconnect the socket or inspect and clear unused cached pages. Navigate between saved pages offline; the counters remain read-only until reconnect.

## Current scope

Snapshots are rendered HTML, not serialized LiveView processes. Offline presentation removes LiveView ownership and bindings, strips resource loads and scripts, and restores a limited markup allowlist. It does not remount arbitrary hooks or reproduce every widget. It provides no queued mutations, durable form drafts, service worker or cold offline startup shell. A native WebView can host the same server application; Fog of War itself does not embed a BEAM runtime.

## Package checks

From the package checkout:

```bash
mix deps.get
mix test
mix hex.build
```

The last command builds a local archive; it does not publish to Hex.

The browser suite for the packaged tools runs with `bash test/browser/run.sh` in this workspace. It reuses installed Chrome and the assessment’s Playwright installation, starts a dedicated test endpoint on port 47182, and verifies navigation/offline lifetime, style isolation, two-tab clearing protection and the no-Web-Locks fallback.

## Native WebView wrappers

See [Generate a WebView app from a LiveView site](WRAPPERS.md) for the shared `.fow.json` manifest, explicit public-page export, and `mix fow.gen.mob` / `mix fow.gen.elixirkit` tasks. The generated hosts contain public assets and a small local runtime; they do not contain your source Phoenix server.

Startup recovery design: [ADR 0001 — preserve the cached page while normal Phoenix bootstrap recovers](docs/adr/0001-seamless-public-startup-recovery.md). This is a proposal with recorded probes and a platform rollout gate; the current wrapper generators still use the earlier manual handoff.

## Styling offline pages and navigation

Fog of War toggles `fow-offline` on `<html>` when its coordinator enters offline mode (including the developer tools' Pause control). Add `class="fow-nav"` to a navigation link, or a container around navigation links. Fog of War toggles `fow-nav-uncached` when that link's destination is unavailable in the usable cache; a container gets the class if any of its links is unavailable. The classes update after navigation and cache changes, including changes from other tabs. Unmarked elements are left alone.

```heex
<.link navigate={~p"/counters/one"} class="my-container fow-nav">
  <span class="my-thing">Counter one</span>
</.link>
```

```css
.fow-offline .my-container.fow-nav .my-thing { color: #916018; }
.fow-offline .my-container.fow-nav.fow-nav-uncached .my-thing { opacity: .4; }
.fow-offline .my-container .my-thing { /* Any offline presentation. */ }
```

`fow-nav-uncached` is maintained online too, so its usual styling should be scoped beneath `.fow-offline`. “Cached” follows the same lookup rules as offline navigation: same origin, no query string, a compatible snapshot build and schema. A hash uses its page's cached snapshot. These classes describe availability; the coordinator still blocks offline server actions and unavailable navigation. They do not imply that an element is disabled or add an accessibility state. Style your server-action buttons separately; the Counter example dims them while offline.


## Examples and tests

- [Counter](examples/basic): a small counter site with directional page transitions. Run it on port 47180.
- [Frontier](examples/frontier): a separate LiveView app with an isometric RTS-style reconnaissance map and constrained travel routes. Run it on port 47190.
- Native wrapper projects are generated beneath each example’s ignored `.fow/apps` directory. See [WRAPPERS.md](WRAPPERS.md).

Each example is its own Mix project. From its directory, run `mix deps.get`, `mix assets.setup`, `mix assets.build`, then `mix phx.server`. The library is a local path dependency; neither example depends on the other.

Run `mix test` in the package and each web example. Automated browser tests, cold-start fixtures, and their pinned Playwright dependency live in [test/browser](test/browser/README.md). Build products, downloaded dependencies, crash dumps, and captured browser results are ignored by Git.

## Optional view transitions

Use the same update helper for LiveView's document patch callback and Fog of War's cached navigation:

```javascript
import {FogOfWar, installFogOfWar, createFogOfWarTransitions} from "fow"
const transitions = createFogOfWarTransitions()
const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {FogOfWar},
  dom: {onDocumentPatch: transitions.onDocumentPatch},
})
installFogOfWar(liveSocket, {transition: transitions.navigate})
liveSocket.connect()
```

Give the moving content a CSS `view-transition-name`. The Counter example's stylesheet demonstrates left/right animation using `html[data-fog-of-war-direction="forward"]` and `"back"`, leaving its header and developer tools fixed. Previously visited routes determine direction; a newly visited shallower route is treated as back. Ordinary events on the same route do not animate. Unsupported browsers and reduced-motion preferences use immediate updates. This is a navigation animation, not an interactive finger-tracked swipe gesture.

For non-link navigation decoration, `class="fow-nav" data-fog-of-war-to="/destination"` explicitly supplies a destination; the Frontier map uses this for sectors that currently have no direct travel link. This attribute controls styling, not navigation permission.

## Compressed browser storage

New snapshots gzip their HTML and store the compressed bytes directly in IndexedDB. Route, build, title and timestamp metadata are stored separately, so startup reads the route directory without loading every page's HTML. Offline navigation reads and decompresses only the requested region; successful online navigation uses LiveView and saves the result afterward. Browsers without the native compression/decompression APIs save plain HTML.

Compression uses the browser's built-in streams and adds no JavaScript dependency. Writes preserve capture order, and other tabs receive cache-change notifications after commits. The inspector shows decoded HTML. Compression reduces storage; it does not encrypt cached content.

Existing plain and gzip/base64 localStorage records migrate automatically. Each source record remains until its IndexedDB transaction commits; unreadable records and records that could not migrate stay in localStorage. A newer compatible device record wins over an older legacy copy. A later IndexedDB quota error does not silently switch the cache to another backend.

The temporary route directory belongs to Fog of War's JavaScript in the browser tab or native WebView. It is rebuilt from IndexedDB at startup and updated after captures, imports and cross-tab changes. Native Elixir code does not maintain a second directory.


### Developer-tool layout and navigation history

Drag anywhere in the header to snap to a corner or the top/bottom center. Controls still respond to ordinary clicks. During dragging, highlighted dock targets and a label beside the pointer show where the panel will land; Escape cancels. Corners allow width/height resizing with the corner handle. Top and bottom centers span the viewport and have a full-width resize strip with a centered grip on the free edge. Drag the vertical divider to resize the list/detail split. Arrow keys operate the grip, resize handle and divider. Layout preferences use sessionStorage and survive live navigation and reloads. They are separate from the cached pages in IndexedDB.

Navigation events are bounded to 200 records in this document's memory. They never enter persistent storage or the exported public bundle. A full reload starts a fresh timeline, including any new initial LiveView arrival. An attempt is updated when the navigation completes or is denied; a stored page remains a separate record showing its latest capture. Clear nav removes only these events; Clear unused retains its existing cross-tab protection. Help explains read-only remembered pages, server-driven UI, stale values and the difference between record versions and compatibility tags.

### Working on the package through an example

Both examples depend directly on this checkout with `{:fow, path: "../.."}`. Run `mix phx.server` from `examples/basic` or `examples/frontier`, then edit the package normally. No `mix deps.update` or copying files is needed. In development, Phoenix watches the package’s Elixir and static asset directories and recompiles `:fow` alongside the example. Esbuild watches the imported package JavaScript. Saving a component, JavaScript, or stylesheet refreshes the page; the DevTools stylesheet requires a full refresh because it is embedded in the component’s shadow-root template.

Restart the example server after changing configuration or dependencies in `mix.exs`. Use an online tab while developing: automatic refresh replaces the current document, so a deliberate offline test can be interrupted by saving files. A full reload also remounts the sticky developer tools; ordinary live navigation retains the existing instance. These watcher settings belong to the example apps, not production consumers of the package.

### Export public preload records without browser tooling

`mix fow.export.cache --env dev --output .fow/cache/dev --debug` fetches the selected public routes and writes a path index plus binary gzip records using Elixir alone. Manifest `envs` override top-level defaults recursively; lists replace rather than concatenate. Native generators accept the same `--env` selection, and flat schema-1 manifests remain supported. See [environment selection and cache export](WRAPPERS.md#environment-overrides-and-browser-free-cache-export) for the format, debug output, and current limits. The browser importer reads this index and commits the compressed records to IndexedDB in bounded batches; see below.


### Importing a public bundle

After `installFogOfWar` returns the coordinator, its cache can import the files produced by `mix fow.export.cache`:

```js
const fogOfWar = installFogOfWar(liveSocket)
liveSocket.connect()
await fogOfWar.cache.importBundle("/offline-bundle/index.json", {
  batchSize: 16,
  byteBudget: 1024 * 1024,
  onProgress: ({completed, total}) => console.log(`${completed}/${total}`)
})
```

Serve the index and its `pages/` directory together. The index's origin must match the page's actual origin and its records must match the client's compatibility build. The importer verifies each compressed file's SHA-256 and byte count before writing. Existing compatible pages captured on the device are preserved, even if the bundled capture is newer. A newer bundle may replace an older bundled record. Completed batches and their progress marker commit in one transaction, so calling the importer again after interruption or reload resumes missing work. Pass an `AbortSignal` as `signal` to stop between batches or cancel a fetch.

`batchSize` limits routes per transaction; `byteBudget` limits buffered compressed payload bytes. A single record may exceed that budget, up to the importer's current 2,100,000-byte compressed-record limit. The importer processes one payload at a time and yields between committed batches. It does not decompress all pages at startup. Bulk importing requires IndexedDB; the smaller fallback cache still accepts ordinary captures.

A native host can pass a parsed index plus `readAsset: async (relativePath, {signal}) => Uint8Array` instead of serving bundle files over HTTP. That bridge must return the original gzip bytes; do not base64-encode them. The native wrapper generators have not yet wired this importer into their startup flow.

`await fogOfWar.cache.ready` waits for backend selection and migration; it resolves to `"indexedDB"`, `"localStorage"` or `"memory"`. `await fogOfWar.cache.flush()` also waits for pending captures. Browser storage remains subject to quota and eviction; importing a bundle does not grant persistent-storage permission.

On macOS, `node test/native/frontier-outage.cjs` exercises a freshly generated WKWebView app through an actual Phoenix process outage and restart.
