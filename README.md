# Fog of War for Phoenix LiveView

<p class="fow-overview-logo"><img src="assets/logo.png" alt="Fog of War: LiveView Offline" width="300"></p>

LiveView is great. Offline is also great. Fog of War is an approach to fairly easy offline, which can work for a wide variety of LiveView apps.

## What's 'Fog of War'?

'Fog of War' was an idiom from old Real-Time Strategy games. Like an explored part of a game map, it shows what was there the last time you looked!

Specifically, if you're offline, this library shows the last markup that the LiveView loaded with.

Unvisited screens are still unavailable, but you can style links to them gracefully. You can navigate around the screens you've already seen. And, for mobile, where the first visit might be while offline, you can create a bundle of important screens to 'pre-explore' the map.

If you immediately have questions, like "What?! Why?!", see the [Rationale and Approach](rationale.html), which goes into some more detail.

## Example apps

| Counters | Fog of War: LiveView Offline |
| --- | --- |
| [![Counters index](screenshots/counters.jpg)](https://fow-counters.fly.dev/) | [![Multiplayer map](screenshots/frontier.jpg)](https://fow.fly.dev/) |

Visit [Counters](https://fow-counters.fly.dev/) to see a basic offline/online demo. And [Fog of War: LiveView Offline](https://fow.fly.dev/) for a multiplayer game where we use it to recreate the RTS fog of war idiom, where going offline to travel through places you've already seen is a game mechanic.

Run the example apps yourself as web, desktop, or mobile apps: [example apps quickstart](example-apps-quickstart.md).

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

// 1. import it,
import {FogOfWar, installFogOfWar} from "fow"


const csrfToken = document.querySelector("meta[name='csrf-token']").content
const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},

  // 2. add the hook
  hooks: {FogOfWar},
})

// 3. install FoW on the socket
installFogOfWar(liveSocket)
liveSocket.connect()
window.liveSocket = liveSocket
```


## Usage Example

Use one `FogOfWar` hook per participating LiveView route.

For example, let's imagine two routes in the browser scope in `lib/my_app_web/router.ex`:

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
    <FogOfWar.region>
      <nav>
        <.link navigate={~p"/counter"}>Counter</.link>
        <.link navigate={~p"/notes"}>Notes</.link>
      </nav>
      <h1>Counter</h1>
      <output>{@count}</output>
      <button phx-click="increment">Increment counter</button>
    </FogOfWar.region>
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
    <FogOfWar.region max_age="PT2H">
      <nav>
        <.link navigate={~p"/counter"}>Counter</.link>
        <.link navigate={~p"/notes"}>Notes</.link>
      </nav>
      <h1>Notes</h1>
      <p>{@note}</p>
    </FogOfWar.region>
    """
  end
end
```

Visit both pages while connected. When disconnected, their links and browser Back/Forward can show their saved content. Server actions are disabled and are never queued for replay. Reconnecting after offline navigation fetches the currently displayed route from the server, thanks to Phoenix' already robust reconnection logic.

* **The hook saves only its element and descendants.** Placing it on an inner paragraph would save only that paragraph; navigating back offline would not reconstruct the surrounding LiveView. Fog of War currently restores one saved element for a route, not a composition of separately cached fragments. Put the hook above any routed layout or other content that must be restored as part of that page.
* Fog of War warns in the console when the hooked element is not a direct child of the main LiveView container. Keep the full page inside the hooked element and verify the rendered result with offline navigation.

### Region options

Use `FogOfWar.region/1` to configure the capture hook. In the Notes example,
`max_age="PT2H"` makes the saved page expire two hours after its last online capture.
ISO 8601 examples include `PT2H` (two hours), `P7D` (seven days),
`P1M` (one month), and `P1Y` (one year, counted as 365 days).

Omit it for no time limit. Offline visits do not extend the lifetime.
The same policy applies to bundled route snapshots from the time of export.
The native startup document is separate from the route cache.

A plain `phx-hook="FogOfWar"` uses the current path after LiveView updates the
browser URL. `FogOfWar.region` takes optional attributes such as an explicit
`path` when you need to supply the route yourself. Offline lookup currently
supports same-origin paths without query strings.

```heex
<FogOfWar.region user_id={@current_user && @current_user.id} require_user_id>
  ...
</FogOfWar.region>
```

Use a stable server-assigned ID (including the tenant if needed). A region with
an ID saves only to that account. Offline lookups check the active account first,
then the public cache. An omitted ID saves publicly by default. Set
`require_user_id` to skip capture when the ID is missing. Bundled routes are
public, and the exporter rejects account-scoped regions.

Account scoping controls normal cache lookup. New gzip payloads written to IndexedDB use AES-GCM with a shared,
non-exportable browser key stored in IndexedDB. Paths and other metadata remain
readable. Same-origin scripts with access to the key can decrypt the payloads.
Existing records are encrypted when rewritten. Plain HTML and storage fallbacks
remain unencrypted. If upgrading an app that previously cached
signed-in HTML without scoping, clear that old cache before enabling this feature.

## Browser storage

- FoW saves rendered HTML by URL path in IndexedDB. It falls back to localStorage, then to memory for the current document.
- New gzip payloads in IndexedDB are encrypted with a browser-generated key. Paths and other metadata remain readable. Plain HTML and fallback storage remain unencrypted.
- A region with a user ID saves to that account. Offline lookup checks the active account first, then public snapshots. Bundled routes are public.

Use the developer tools below to inspect saved pages, storage usage, and navigation events.

### Optional account keys

See [Cache security](FogOfWar.html#module-cache-security) for the config
entry and authenticated router line that enable FoW's built-in endpoint.
The callback takes a connection and returns the trusted account scope.
FoW requests the key automatically when a signed-in region renders.

Wrap your existing logout link, button, or form with `FogOfWar.logout/1`.
FoW clears the shared key before forwarding the action. Phoenix handles
session logout and any page refreshes.

Clear existing private FoW snapshots before rolling out the new policy,
including any copies made by older tabs that are still open. The first
successful unlock also removes old private snapshots from the available
storage. If rolling back, wipe FoW browser storage before using the previous
policy again. Public bundles use the same format in either mode.

## Developer tools

See `FogOfWar.dev_tools/1`.

![Fog of War DevTools docked in the lower-right corner of Counters](screenshots/counters-dev-tools.jpg)

## Desktop & Mobile

### Create the manifest

From your Phoenix app directory, run:

```sh
mix fow.manifest --name "My App" --url http://127.0.0.1:4000
```

Review and commit `.fow.json`. Set `startup.path` to the page the app should
open and list any additional offline routes in `preload.paths`. Use routes
whose anonymous HTML and assets you can ship publicly. Set `web.origin` to the
website the app should connect to. Named profiles under `envs` can override
these settings, including the origin and native app identifier. Select a profile
with `--env`.

Start Phoenix and leave it running while you generate from a local origin.
The [example apps quickstart](example-apps-quickstart.md) is a good way to
check your macOS or Android toolchain before wrapping your own app.

### Build and run on macOS

From your Phoenix app directory, prepare the bundle, build, and install the app
with one command:

```sh
mix fow.desktop --env dev
open "$HOME/Applications/My App.app"
```

The generated source lives in `.fow/dev/projects/desktop/`. Use `--force`
to replace a previous generated project and installed app.

### Build and run on Android

Add an Android-only profile to the manifest under `envs`:

```json
"android-dev": {"mob": {"platforms": ["android"]}}
```

From your Phoenix app directory, prepare the bundle and generate the project:

```sh
mix fow.bundle.prepare --env android-dev --platform android
mix fow.gen.mobile --env android-dev
cd .fow/android-dev/projects/mobile
```

With an emulator running, forward the port if your website uses local loopback
(substitute the port in your manifest), then build and deploy:

```sh
adb reverse tcp:4000 tcp:4000
./build.sh --android
```

Open the app from the emulator's launcher. You can also open the generated
`android/` folder in Android Studio. For repeat builds, move aside the previous
prepared bundle and pass `--force` to the generator to replace its project.
Generate into a tracked directory if you plan to keep native edits.

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

`fow-nav-uncached` is maintained online too, so its usual styling should be scoped beneath `.fow-offline`. “Cached” follows the same lookup rules as offline navigation: same origin, no query string, a compatible snapshot build and schema. A hash uses its page's cached snapshot.

These classes describe availability; the coordinator still blocks offline server actions and unavailable navigation. They do not imply that an element is disabled or add an accessibility state. Style your server-action buttons separately; the Counter example dims them while offline.


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


## Contributing

### Tests

Run `mix test` in the package and each web example.

Automated browser tests, cold-start fixtures, and their pinned Playwright dependency live in [test/browser](test/browser/README.md).

### Working on the package through an example

Both examples depend directly on this checkout with `{:fow, path: "../.."}`. Run `mix phx.server` from `examples/basic` or `examples/frontier`, then edit the package normally. No `mix deps.update` or copying files is needed. In development, Phoenix watches the package’s Elixir and static asset directories and recompiles `:fow` alongside the example. Esbuild watches the imported package JavaScript. Saving a component, JavaScript, or stylesheet refreshes the page; the DevTools stylesheet requires a full refresh because it is embedded in the component’s shadow-root template.

Restart the example server after changing configuration or dependencies in `mix.exs`. Use an online tab while developing: automatic refresh replaces the current document, so a deliberate offline test can be interrupted by saving files. A full reload also remounts the sticky developer tools; ordinary live navigation retains the existing instance. These watcher settings belong to the example apps, not production consumers of the package.
