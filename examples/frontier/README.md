# Frontier

A separate Phoenix LiveView example: explore six locations on an isometric reconnaissance map. Each location is a route. Only the trails listed at that location are navigable; there is no arbitrary jump link to every sector. No database, game engine, or Counter application code is required.

```sh
cd examples/frontier
mix deps.get
mix assets.setup
mix assets.build
mix phx.server
```

Open http://127.0.0.1:47190. Visit a few locations, open the floating Fog of War tools, and pause the connection. Explored destinations retain their saved reports; unknown destinations remain black and cannot be visited offline. Cached terrain is dimmed and dithered; current terrain is lit while online. Survey is a server event, disabled in cached presentations. The little scout uses a CSS arrival animation. This is route navigation, not a real-time simulation or a pathfinding engine.

The map and command panel form the one top-level `FogOfWar` region. Each sector supplies `data-fog-of-war-to` so its cache state can be styled even where no direct trail exists. The Counter example remains independent at `examples/basic`.

## Artwork

A single 550×550 sprite sheet (~70 KB) from Kenney's **Medieval RTS** pack is bundled locally. The art is **CC0**, separate from this repository's MIT code license. Its original sprite coordinates are included as XML. See [ASSETS.md](ASSETS.md) for provenance and official license links.
