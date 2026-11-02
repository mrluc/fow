# Fog of War browser tests

These use **Playwright Test and the installed Google Chrome**, not Puppeteer. `run.sh` uses the Node and Elixir tools on your PATH and its own pinned Playwright installation. It builds the Counter example's JavaScript, starts an isolated test server and shuts that server down when the run ends. It leaves the normal example at port 47180 alone. Install dependencies once with `npm ci --prefix test/browser`. Google Chrome is the default; alternatively run `npx --prefix test/browser playwright install chromium` and set `FOG_OF_WAR_BROWSER_CHANNEL=chromium`.

From the repository root (`fow`), first run `mix deps.get` in the root, `examples/basic`, and `examples/frontier`, then `mix assets.setup` in both examples. The pinned tool versions are in `.tool-versions`.

From the repository root:

```sh
# All browser tests.
bash test/browser/run.sh

# Stock LiveView session/reload behavior, including a genuinely expired token.
bash test/browser/run.sh startup-session.spec.cjs

# Browser model of the proposed cached-document/live-document handoff.
bash test/browser/run.sh startup-model.spec.cjs

# Watch the browser; use Playwright's inspector to pause/step if desired.
bash test/browser/run.sh startup-model.spec.cjs --headed
PWDEBUG=1 bash test/browser/run.sh startup-model.spec.cjs
```

## Test files

| File | What it proves |
|---|---|
| `dev-tools.spec.cjs` | Persistent package-owned dev tools, offline navigation/Back, protected cache clearing across tabs, lockless fallback, and legacy cache-key replacement |
| `cold-liveview.spec.cjs` | Complete baked LiveView HTML/client/assets, an empty browser data store, offline retries, normal stale-session recovery, and recovery at the final baked route after disconnected navigation |
| `startup-session.spec.cjs` | Stock LiveView recovers from expired signed data, a missing cookie, or mismatched CSRF state; also characterizes the cached-content loss when its automatic page request fails |
| `startup-model.spec.cjs` | Cached navigation survives failed candidate loads; a real but not-yet-joined candidate does not take over; successful mount commits automatically; cancelled/old route callbacks cannot take over |

`startup-session.spec.cjs` intentionally records an undesirable upstream behavior as a **characterization test**. A passing “page is lost” assertion demonstrates the failure we must protect against; it does not claim Fog of War recovery is implemented or correct. The successful-network cases additionally require a real server-side counter increment.

The expired fixture preserves the original signed payload, signs it 30 days in the past, checks its signature with age verification disabled, and checks that LiveView itself returns `{:error, :expired}`. This isolates expiration from bad signatures and from cookie/CSRF failure. Its signing code exists only in `scripts/browser-fixtures.exs`, loaded by the test runner. Production examples, generated hosts and the published library do not install this fixture.

The two-document model is in `support/startup-model.js`. It is **test-only exploratory code**, not a production recovery coordinator. Two same-origin iframes stand in for two WebViews with a common website data store. The live iframe runs the actual Counter site; Playwright forwards its real WebSocket traffic while selectively holding channel join replies. The fixture's small readiness bridge forwards the routed FogOfWar hook's capture event. The test requires server behavior after commit; it does not merely assert a fake readiness flag.

The model's `online` event is a deterministic retry trigger. Capped background retry, real OS connectivity notifications, native stacking/accessibility/focus, history, app lifecycle and per-platform cookie behavior still need native tests before rollout. The model's initial host document is supplied by the test server; it is not proof that a native first installation can boot its assets without any network.

## Runner and fixtures

`playwright.config.cjs` runs one worker, zero retries, and retains traces/screenshots on failure under `results/dev-tools-browser`. The main Counter test endpoint listens at 47182. A test-only Bandit listener at 47183 delegates to the same endpoint and adds response transformations and the model page; it starts after the main endpoint. The runner waits for both by probing 47183. Neither test port should already be occupied.

`server.sh` starts `scripts/browser-server.exs`, which loads `scripts/browser-fixtures.exs`. The permanent tests use real HTTP responses for the transformed pages, rather than depending on synthetic top-level browser responses. The model reads the permanent public bundle fixture at `test/browser/fixtures/public-bundle.json`, copied from a reviewed export of the Counter example. It does not require a leftover `.fow` build folder. Refresh the fixture deliberately when changing the example's pages; tests do not silently make missing offline content appear.

Other checks remain separate: `wrapper-smoke.cjs` is a standalone smoke check for a running generated public-shell host, and `docs/adr/probes/` contains the earlier source/native characterization probes. [ADR 0001](../../docs/adr/0001-seamless-public-startup-recovery.md) records the proposed startup contract and native rollout gate.

## Full rendered LiveView cold-start tests

Run `bash test/browser/run.sh cold-liveview.spec.cjs` from `elixir-client/fow`. The server fixture captures a complete anonymous render and its actual application JS/CSS, retaining LiveView/static tokens and CSRF metadata while discarding response cookies. Tokens are genuinely signed 30 days in the past and verified expired. The browser begins with no cookies or localStorage state.

A real local loader fixture serves the initial saved HTML at the expected route without calling Phoenix or setting cookies. Before the bundled application JS executes, the first test enables actual browser offline mode. It observes repeated failed sockets with the page still visible, then restores connectivity and requires a `stale` reply, exactly one fresh page request at the current route, and a server increment. This starts offline at client boot, not before the fixture has delivered the HTML bytes; native file delivery remains platform-specific.

The second test keeps the browser's local bundle supplier reachable while making the backend's socket endpoint return 503. Baked-page links therefore use ordinary full-document disconnected navigation, loading the other bundled LiveView documents. Once the backend returns, the normal client refreshes the final route automatically. This is not same-document offline snapshot navigation, a second WebView, or a forced socket reconnect.

Synthetic top-level HTML delivery initially triggered Chrome's local-network access checks on reconnection. The tests do not grant permissions or disable checks: they use real fixture HTTP delivery for the document. The actual browser context receives no build-time response cookies and never warms up against the live application. Results apply to the pinned client/server and this loading model; native origin/assets and cross-version compatibility remain rollout checks.

The independent Frontier app is exercised by `frontier.spec.cjs`, on port 47192. Counter/fixture servers use 47182 and 47183. `transitions.spec.cjs` tests directional online/offline navigation and reduced motion. `FOG_OF_WAR_BROWSER_NODE_MODULES` can override the local browser dependency directory.
