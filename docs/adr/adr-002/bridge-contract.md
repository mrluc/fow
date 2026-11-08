# ADR-002 native bundle read contract

The JS client can import its native bundle through one deliberately small host API:

```js
window.__fogOfWarNativeBundle = { indexURL: 'fog-of-war-assets://bundle/__fog_of_war_bundle/index.json' }
window.__fogOfWarNativeReadAsset = async (relativePath, {signal} = {}) => /* bytes or Base64 */
```

Install both values before the Fog of War client starts. The reader receives paths relative to the directory containing `indexURL`: first `index.json`, then each validated `pages/...` record path from that index. It must only read files from the generated public bundle root. It must reject unknown paths, honor abort when practical, and return the original file bytes as `Uint8Array`, `ArrayBuffer`/view, or Base64 text. Base64 is accepted for bridges that cannot return binary values directly; page gzip bytes are decoded before checksum verification and decompression. No arbitrary filesystem path is exposed to page JavaScript.

The importer parses the returned index as UTF-8 JSON, retains the `indexURL` directory as the page-asset base, and uses the same reader for gzip records. If the host reader is absent, existing HTTP URL input and Android loopback fetch behavior remain unchanged. The API is intended for reading exported bundle files only, not scripts, stylesheets or general network access.

## Native wiring needed

- **WKWebView/iOS/macOS:** the generated `fog-of-war-assets://` scheme can serve ordinary CSS and image resources, but the recorded probe found `fetch`/CORS requests blocked. Inject `__fogOfWarNativeBundle` before page scripts, then implement the reader with a `WKScriptMessageHandler` request/reply channel (unique request IDs, path allowlist, Base64 reply) or an equivalent native promise bridge. Do not rely on `fetch(indexURL)` for the custom scheme.
- **Android WebView:** the current Mob view exposes a one-way `MobBridge.postMessage(json)` JavaScript interface and injects its seed only when document-start script support exists. That interface does not return a promise or read assets. Wire a request/reply callback (or an async JS interface backed by a fixed asset-root allowlist), and inject both bundle metadata and the reader before Fog of War startup. Without that bridge, the existing loopback server remains the working path.
- **Desktop Tauri smoke template:** it currently uses an initialization script and a local HTTP server for the smoke import; it has no bundle reader bridge. Its `initialization_script` can install the bundle metadata early, but native command/plugin wiring is still required to implement the callback.

The native side must derive/hold the bundle root from trusted app configuration, normalize and allowlist the relative name, then return only the requested asset bytes. The JS API does not accept absolute paths or caller-selected roots.
