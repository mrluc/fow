# Counter

A small LiveView site with a counters index and three counter pages. The routed pages opt into Fog of War so their complete rendered state can be revisited offline. The developer panel is a separate sticky LiveView, fixed at the lower right in development only.

Start it from this directory with `source ../../../env.sh && mix phx.server`. Open `http://127.0.0.1:47180/`.

The app's content contains only the counter experience. Its shared layout includes `<FogOfWar.dev_tools socket={@socket} />` from the parent package, and `config/dev.exs` enables it with `config :fow, dev_tools: true`. The package owns the sticky LiveView, its hook, isolated styling, connection control and cache explorer. The example has no panel-specific JavaScript or CSS. Other environments leave it disabled by default.

Expand the launcher to use Connection or Cache. The cache table shows path, storage estimate, saved time, build and whether the route is open. Select a row to inspect metadata and HTML. Clear unused preserves routes open in cooperating Fog of War tabs, including the current tab, and does not touch other localStorage entries.

Each counter page has its own path and cached page state. Navigate from the index to a counter, increment it, visit another, then pause the connection from the developer panel and move among cached pages. Counter actions are unavailable while disconnected. Reconnect reloads the currently viewed route from the server.

The demo uses the package from the parent checkout via `{:fow, path: "../.."}`. Its normal asset import remains `import {FogOfWar, installFogOfWar} from "fow"` in `assets/js/app.js`.
