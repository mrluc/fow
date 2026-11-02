# Startup investigation probes

The routine browser tests are now in [`test/browser`](../../../test/browser/README.md). Use those for repeatable genuine-expiry and two-document recovery checks. These probes preserve earlier investigation evidence and the small native WebKit checks; they do not enable startup recovery in any generated app.

`liveview-bootstrap.cjs` is the original stock-client characterization. It supplies HTML to an already established same-origin document, tries fresh/missing/invalid session state, and blocks an automatic HTTP refresh. Its invalid token is not an expired signature; the permanent Playwright fixture now tests genuine expiration. Results from that earlier probe are in `results/liveview-bootstrap-characterization.json`.

`webkit-origin.swift` loads a small HTML string at a configured HTTPS base URL in a nonpersistent native macOS WebView and checks the reported origin, secure context and localStorage. `webkit-liveview.swift` fetches fresh Counter HTML through an ephemeral native HTTP session, explicitly transfers its response cookies to a nonpersistent WebView, loads the HTML at the intended URL, waits for the actual root to join, clicks Increment and checks the server-updated count. These exit nonzero on failure. They are macOS probes; cookie transfer, HTTPS server delivery, offline assets and iOS behavior are not established by them.

With `test/browser/server.sh` running, from `elixir-client/fow`:

```sh
swiftc docs/adr/probes/webkit-origin.swift -o /tmp/fog-of-war-webkit-origin
/tmp/fog-of-war-webkit-origin
swiftc docs/adr/probes/webkit-liveview.swift -o /tmp/fog-of-war-webkit-liveview
/tmp/fog-of-war-webkit-liveview http://127.0.0.1:47182/counters/three
```

The native outputs are recorded in `results/webkit-origin-probe.txt` and `results/webkit-liveview-probe.txt`. Private LiveView fields used to inspect readiness in a probe are not being proposed as a stable production interface. See [ADR 0001](../0001-seamless-public-startup-recovery.md).
