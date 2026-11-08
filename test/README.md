# Fog of War tests

Run these commands from the FoW checkout. For this workspace, source `../env.sh` first to select the installed toolchain.

| Layer | Command or entry point | Coverage |
| --- | --- | --- |
| Library and wrapper generation | `mix test` | Component and developer-tool irendering, manifests, cache and asset export, native bundle preparation and inlining, mobile generation, desktop build/install orchestration. Build and install unit tests use a fake command runner. |
| Game rules and inspector | `(cd examples/frontier && mix test)` | Pure state stepping, cooldowns, health and respawn, reconnect authorization, ETS enforcement and two LiveViews observing a manual game. |
| Phoenix examples | `(cd examples/basic && mix test)` and `(cd examples/frontier && mix test)` | Counters and error pages, Frontier routes and map rendering. |
| Browser integration | `bash test/browser/run.sh` | Playwright tests for cache migration, compression, IndexedDB, developer tools, offline navigation, history, map motion, and cold startup or stale-session recovery. Network failures use browser interception or fixture gates. See [browser test setup](browser/README.md). |
| macOS process outage | `node test/native/frontier-outage.cjs` | Real generated WKWebView app with Phoenix stopped and restarted while the window stays open. |
| Android device smoke tests | `test/native/mob-counters.exs` and `test/native/mob-frontier.exs` | Cold offline navigation and recovery in the generated Android wrapper using removal and restoration of adb forwarding. The server remains running. Frontier's older visual checks still assume canvas fog. |
| Platform experiments | `docs/adr/probes/` and `docs/adr/adr-002/` | Standalone probes for origin and session behavior, custom schemes, loopback requests, and asset rendering. |

The Ubuntu CI job runs the library and web example ExUnit suites and the Playwright suite. Native tests need their platform toolchains and run separately.

## macOS process outage test

```sh
source ../env.sh
node test/native/frontier-outage.cjs
```

Leave port 47192 free. The runner builds the example assets, starts its own Phoenix process, and generates a temporary desktop project from a fresh Apple bundle. It launches a separate test executable using the configured Cargo target directory. The installed Frontier app and the regular dev server on port 47190 are outside the test.

Once LiveView joins, the runner terminates Phoenix and checks that the origin is unreachable. The open WebView must render a cached tile, reject an uncached tile, and handle Back and Forward offline. The runner then starts a new Phoenix process on the same port. The WebView must rejoin the route selected offline and navigate live to the formerly uncached tile. The test uses Frontier's HTTP loopback origin.
