# ADR-002 native observations

2026-11-04, macOS 15.1 (24B83), system WKWebView, fresh nonpersistent website data store. Startup HTML supplied with the public loadSimulatedRequest API at `https://fow-images.invalid/start`. No web-security switches or ATS exceptions. These are macOS results, not an iOS certification. The image fixture is a tiny SVG; the CSS filter test makes half of it transparent.

| HTTPS document loading… | Custom scheme | HTTP 127.0.0.1:47186 | HTTP localhost:47186 |
| --- | --- | --- | --- |
| Plain img | Displays | Blocked | Displays |
| CSS background | Paints | Blocked | Paints |
| Anonymous CORS image | Blocked | Blocked | Blocked |
| fetch / readable bytes | Blocked | Blocked | Blocked |
| External script / stylesheet | Blocked in earlier native probe | Blocked | Blocked |

The local fixture sends Access-Control-Allow-Origin for the exact HTTPS test origin. Rejected HTTPS script/style/CORS/fetch requests did not reach its request handler. Do not attribute those failures to missing CORS response headers. The probe does not identify the internal WebKit rejection mechanism conclusively; potentially-trustworthy status alone did not make these requests succeed.

HTTP control: page logical origin `http://127.0.0.1:47180`; assets remain cross-origin on port 47186. Plain images, CSS backgrounds, external scripts, styles, CORS images, fetch and CORS-enabled canvas readback work with matching CORS headers. (The final rerun included an origin-matched CORS response.) Plain non-CORS images still taint canvas, as expected.

CSS filter test, HTTPS document and custom-scheme image: `brightness(.45)` produces native snapshot RGB `[0,97,0]` in the visible green half and `[255,255,255]` in the transparent half over the white page. Same result for img and CSS background. This validates alpha-preserving display, not JavaScript readback. Screenshot sampling accounts for Retina scaling.

Reproduce from the repository root, on macOS with Swift:

```sh
python3 docs/adr/adr-002/loopback-assets.py
```

In another terminal:

```sh
swift docs/adr/adr-002/loopback-probe.swift
swift docs/adr/adr-002/loopback-probe.swift --localhost
swift docs/adr/adr-002/loopback-probe.swift --http
swift docs/adr/adr-002/css-filter-probe.swift
```

Stop the fixture with Ctrl+C afterward. It binds only to 127.0.0.1, serves three fixed assets, and allows only the two fixture origins. These are characterization probes that print observations, not production servers or assertions of universal compatibility.
