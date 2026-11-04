# Generate a WebView app from a LiveView site

## Environment overrides and browser-free cache export

The manifest supports arbitrary named environments under `envs`. All other configuration at the top level supplies defaults. Nested maps merge recursively; arrays and scalar values replace the default value. Required values are validated **after** resolving the selected environment, so a required setting may exist only in an environment. Control fields (`schema`, `envs`, `default_env`, `environment`) cannot be overridden inside an environment. Environment names use letters, digits, underscores, and hyphens; they remain strings, not dynamically created Elixir atoms.

```json
{
  "schema": 2,
  "default_env": "dev",
  "app": {
    "name": "Counters",
    "slug": "counters",
    "identifier": "dev.example.counters",
    "version": "0.1.0"
  },
  "web": {"origin": "http://127.0.0.1:47180", "start_path": "/"},
  "public": {
    "paths": ["/", "/counters/one"],
    "static_root": "priv/static",
    "asset_directories": ["assets", "css", "fonts", "images"],
    "bundle": ".fow/public"
  },
  "envs": {
    "dev": {},
    "testflight": {
      "app": {"name": "Counters Preview", "identifier": "dev.example.counters.preview"},
      "web": {"origin": "https://preview.example.com"},
      "public": {"paths": ["/"]}
    }
  }
}
```

`mix fow.export --env testflight` selects that environment. Omitting `--env` selects `default_env`, or `dev` if no default is declared. This is independent of `MIX_ENV`: it chooses the website to capture and the wrapper identity, not the local application's development/test/production configuration. Replace placeholder production/preview domains with a real public deployment before exporting. A missing or invalid environment fails rather than falling back to development.

Resolved public bundle directories automatically gain the environment name: the example above exports to `.fow/public/dev` or `.fow/public/testflight`. Generator defaults similarly use `.fow/apps/mob/<env>` and `.fow/apps/elixirkit/<env>`. Explicit `--output` paths are used as supplied. Existing flat schema-1 manifests retain their original paths and require no migration. Generated wrappers store the resolved manifest, including its environment, rather than carrying unresolved profiles. Generators reject exports whose website origin or environment does not match.

For a build-machine capture address different from the device's website address, set `capture.origin` in defaults or an environment. It defaults to `web.origin`; `--base-url` overrides only the capture address. For example, a build machine can download from loopback while the native app is configured for a device-reachable website. These addresses must be HTTP(S) origins, with HTTPS required outside loopback.

### Export just the compressed public records

```sh
mix fow.export.cache --env dev --output .fow/cache/dev --debug
```

This task runs entirely in Elixir. It downloads each explicitly listed public route's initial HTML response without cookies, JavaScript execution, Playwright, or browser-profile access. It requires exactly one `phx-hook="FogOfWar"` region whose `data-fog-of-war-path` matches the requested route. It parses that element and its descendants, gzips the UTF-8 markup using Erlang's built-in `:zlib`, and writes a binary `.html.gz` file. Each HTML response is limited to 2,000,000 bytes and is processed before moving to the next route; the accumulated index contains metadata, not the HTML collection. No base64 representation is included in these binary files.

The output is `index.json`, `startup.html` (the selected start path's complete, unmodified HTTP response), and `pages/<route-sha256>.html.gz`. Index records contain path, title, region ID, snapshot schema/build, capture time, byte counts, and a payload checksum. The index also records the selected environment, intended app origin, and capture origin. New exports refuse an existing destination and publish the output directory only after all pages succeed.

`--debug` additionally retains per-route request method/URL, complete response HTML, and extracted region HTML under `debug/<route-sha256>/`. Debug HTML and `startup.html` can contain anonymous LiveView bootstrap values from the public response; no response cookies or browser state are exported. The standalone cache task does **not** collect assets: it produces records and the initial document for the next loader/import stage. The full public exporter retains its existing allowlisted asset-copy behavior, which uses the local project's static files; matching deployment assets are required when exporting a deployed site.

### Keep existing source generation working

```sh
mix fow.export --env dev
mix fow.gen.elixirkit --env dev
mix fow.gen.mob --env dev
```

The full exporter still produces the legacy public shell and now also places the binary record export under `cache/`. Both native generators copy that cache index, startup document, and listed payloads into their app resources using an explicit file allowlist. This preserves existing shell behavior while providing the new artifacts for the future IndexedDB importer. **Neither IndexedDB import nor seamless native cold-start handoff is implemented by these tasks yet.** The legacy sanitized shell remains separate from the complete startup response stored under `cache/startup.html`.

Generating a source wrapper does not compile Rust, install mobile SDKs, download simulator images, or build native dependencies. The Mob generator invokes `mob.new --no-install` and requires the existing `mob_new` archive. The later `build.sh` step is the expensive native build. Do not use generation success as evidence that an iOS/Android/desktop binary was built or tested.



**Startup design under revision:** the manual “Open live site” flow below is a prototype and does not meet the seamless-startup requirement. [ADR 0001](docs/adr/0001-seamless-public-startup-recovery.md) defines the proposed automatic recovery contract and the platform tests required before rollout. Its configuration is proposed, not implemented.

The generators make small native hosts for an existing website. They do not package its Phoenix server. Both targets consume the same reviewable `.fow.json` and explicitly public HTML export. The desktop target uses ElixirKit with a Tauri WebView. The mobile target uses Mob's existing native WebView component.

This is an experimental first pass. The generated macOS ARM64 Counter app has built and opened its bundled public site. The Mob project compiles, its screen test passes, and its Android/iOS document-start patches apply repeatedly; this new wrapper has not yet been run on a device or emulator. No app-store or production authentication claim is implied.

## Two addresses, two jobs

The app carries a read-only copy of selected public pages. A tiny Elixir server serves those files at an ephemeral `http://127.0.0.1:<port>` address on the device. It binds only loopback and serves only files listed in the bundle. This gives the app something useful to show on its very first offline opening, with normal relative CSS, images and links.

“Open live site” opens the actual website at its normal origin. Login, cookies, LiveView connections and subsequent private caching belong to that site. Its storage is separate from the bundled shell's storage. Before the live site's scripts execute, the native host can seed missing public Fog of War snapshots into the site's localStorage. Existing entries are left untouched. This seeds read-only content, not a signed LiveView session or authentication.

The wrapper currently starts on the bundled public shell every time. It does not automatically detect connectivity, restore a previously authenticated remote document on a cold offline start, or intercept a failed remote load and impersonate its HTTPS origin. Once the remote site has loaded, its ordinary Fog of War coordinator supports cached offline navigation. A remote-origin service worker or another explicit boot/cache design is still needed for remote-origin cold starts.

## Generate a manifest

Add `:fow` to the source Phoenix application's dependencies and run these tasks from that application. Build the site's normal production assets first if that is what you intend to distribute, and have a cookie-free public instance running at the configured origin.

```sh
mix fow.manifest --url https://counter.example --name Counters --slug counters \
  --public / --public /counters/one --public /counters/two
```

The task creates `.fow.json` and refuses to overwrite an existing file unless explicitly given `--force`. Review and commit the manifest. Discovered GET routes are informational: dynamic routes such as `/counters/:id` cannot determine which concrete pages are public, so they are not exported automatically.

```json
{
  "schema": 1,
  "app": {
    "name": "Counters",
    "slug": "counters",
    "identifier": "dev.example.counters",
    "version": "0.1.0",
    "icon": "priv/static/images/logo.svg"
  },
  "web": {"origin": "https://counter.example", "start_path": "/"},
  "public": {
    "paths": ["/", "/counters/one", "/counters/two"],
    "static_root": "priv/static",
    "asset_directories": ["assets", "css", "fonts", "images"],
    "bundle": ".fow/public"
  },
  "mob": {"platforms": ["android", "ios"]},
  "elixirkit": {"width": 1060, "height": 760}
}
```

| Setting | Inferred/default | Review or customize |
|---|---|---|
| App slug/version | Mix project configuration | Native identity and release version |
| Display name/bundle identifier | Derived from slug | Product name and reverse-domain identifier |
| Endpoint/router/routes | Phoenix configuration and route table | `--endpoint` for projects with several endpoints |
| Website origin | Endpoint URL configuration | Prefer explicit `--url`; device-reachable HTTPS for distribution |
| Icon source | Common PNG/SVG/favicon paths | Set `app.icon` to a project-relative branding file |
| Public startup route/pages | No routes are assumed public | Explicit concrete paths; start route must be included |
| Asset directories | Conventional static folders | Add other project-relative public static directories |
| Native platforms/window size | Android+iOS; 1060×760 | Manifest settings |

## Export the public shell

```sh
mix fow.export
```

Only explicit routes are fetched. The exporter sends no browser cookies, follows no redirects, requires HTTP 200 HTML, and uses an isolated HTTP client profile. It copies reachable stylesheets/images and CSS dependencies under the allowed static directories, rejecting symlinks and escaping paths. It strips scripts, signed LiveView ownership/session attributes, CSRF fields, hidden/password inputs and Fog of War dev tools; it disables form controls and adds a local-only resource policy. Its own small bootstrap provides read-only public navigation and the link to the live site. These transformations are experimental and are not a general-purpose HTML security sanitizer; review the exported files and choose public routes deliberately.

A page with a single `FogOfWar` hook exports that complete region as its remote cache snapshot. Otherwise the body is used as a static-shell fallback. Whole-page hooks are the supported navigation unit; multiple opted-in regions on one page are rejected. The remote website still needs the package's normal JavaScript setup for actual Fog of War behavior.

The output contains `bundle.json`, rendered pages, referenced public assets and the trusted bootstrap. No source project directory, BEAM server modules, cookies, database or runtime configuration is copied. HTTP response headers, downloads, arbitrary JS-rendered assets, `srcset` variants and external CDN resources are not exported; host those assets locally or extend the exporter. The resource policy blocks external loads in the bundled shell.

Exports refuse an existing destination. To refresh, export to a fresh directory with `--output .fow/public-v2`, review it, and change `public.bundle` in the manifest. This is intentionally non-destructive while the export contract settles.

## Generate desktop and mobile hosts

```sh
mix fow.gen.elixirkit --output ../counter-desktop
mix fow.gen.mob --output ../counter-mobile
```

Both tasks accept `--manifest path/to/.fow.json`. They refuse existing output folders. The manifest's bundle path is resolved relative to its own directory; output paths are relative to the command's working directory. Generated applications are independent projects and do not depend on `:fow` or the source Phoenix app. Commit the new hosts and their lockfiles after resolving/building them.

The Mob generator requires the upstream `mob_new` archive once (`mix archive.install hex mob_new`). It invokes `mix mob.new --blank --no-install` internally and writes the small wrapper screen, startup, public server, native patch script and build script. Users do not run the scaffold generator or write WebView bridge code for each site. ElixirKit generation writes its small Tauri host directly; no Tauri scaffold generator is needed.

```sh
cd ../counter-desktop
./build.sh
```

The desktop build needs Elixir/OTP, Rust, a Tauri CLI and Xcode command-line tools. It creates an Elixir release containing only the public server/bundle, creates launcher icons from the inferred/custom source, builds the Tauri app and signs the local app ad hoc. This first release recipe is macOS-only; Windows/Linux release and signing steps remain to be implemented and verified. Production notarization/signing is separate.

```sh
cd ../counter-mobile
./build.sh --android
# or, with the platform tools/device/simulator configured:
./build.sh --ios
```

The mobile script fetches dependencies, runs Mob's installation step, applies the native document-start integration and invokes Mob's native deployment. It needs Android SDK/NDK/JDK or Xcode and a compatible simulator/device. Installation can download large OTP runtimes. The icon source is copied to `branding/source.*`; mobile launchers retain Mob's default artwork until applying it with Mob's documented `mix mob.icon` workflow (requires its Image dependency). Desktop artwork is applied by the generated build script.

For this workspace's running Counter demo, the manifest uses `http://127.0.0.1:47180`. Android needs `adb reverse tcp:47180 tcp:47180` to reach the developer machine at that address. Distribution should use a reachable HTTPS origin. The bundled shell works independently of that connection.

## Native integration boundaries

- **Shared runtime:** normal HTTP on device loopback, ephemeral port, read-only allowlisted bundle paths. The port changes on launch, so this public shell's storage is expendable and repopulated from the bundle.
- **Tauri:** a window initially loads the loopback shell. `initialization_script` installs the public cache seed before document scripts. Top-level navigation permits only the selected loopback origin and the configured website origin; no Tauri IPC capabilities are granted to the remote page.
- **Mob Android:** the app-owned `MobBridge.kt` installs `WebViewCompat.addDocumentStartJavaScript` before its first `loadUrl`, with an exact allowed-origin rule and feature detection. Without `DOCUMENT_START_SCRIPT`, the shell still works but remote document-start cache seeding is unavailable and logs a warning. The generated Gradle file includes AndroidX WebKit.
- **Mob iOS:** `prepare-native.exs` patches the pinned dependency's `MobRootView.swift` to add a main-frame-only `WKUserScript` at document start. Reapply after fetching dependencies and rebuild the native host. This is a generated downstream patch, not a new upstream Mob API.
- **Patch maintenance:** native anchors and start/end markers must occur exactly once. Repeated runs replace the existing block, including updated seed data. Unexpected upstream layouts fail visibly rather than silently omitting preload. Mob is pinned to 0.9.27; ElixirKit to commit `16d19dd3fe7ad0c0e38a1667a90ed7962ed477c7`; generated lockfiles pin the rest.

Public snapshots use the same one-record-per-route cache format as the live package. A successful online capture replaces that route and removes its older element-ID variants. There is no private-account namespace or encryption yet; the generated example does not implement login. Adding account-aware caching and logout cleanup is a prerequisite for a real multi-user example. This is separate from selecting a public, distributable preload bundle.

Official integration references: [Tauri initialization scripts](https://docs.rs/tauri/latest/tauri/webview/struct.WebviewBuilder.html), [Android document-start scripts](https://developer.android.com/reference/androidx/webkit/WebViewCompat#addDocumentStartJavaScript(android.webkit.WebView,java.lang.String,java.util.Set%3Cjava.lang.String%3E)), [Android local WebView content](https://developer.android.com/develop/ui/views/layout/webapps/load-local-content), and [WKWebView HTML base URLs](https://developer.apple.com/documentation/webkit/wkwebview/loadhtmlstring(_:baseurl:)). A base URL should not be assumed to offer the same origin/loading contract across all these hosts.

## Checked in this workspace

The source example is `examples/basic`, its manifest is `examples/basic/.fow.json`, and its exported bundle is `examples/basic/.fow/public`. Generated projects are `examples/wrappers/elixirkit` and `examples/wrappers/mob`. Use the shared workspace `elixir-client/env.sh` when reproducing with the installed tools/cache; generated projects themselves do not depend on that script.

Validation: seven package tests, five Counter LiveView tests, four dev-tools browser tests and one Mob screen test pass. `test/browser/wrapper-smoke.cjs` verifies actual generated public-shell navigation/back, disabled actions, absence of signed session data, no external requests, document-start seeding, origin restriction and no overwrite of existing state. It runs with `PUBLIC_SHELL_URL` set to the generated host's printed readiness URL and the workspace Playwright installation in `NODE_PATH`. The screenshot is `results/wrapper-public-shell.png`.

The generated macOS app is at `elixir-client/.cache/tauri-target/release/bundle/macos/Counters.app` when built using the shared workspace cache. Its window was inspected showing the bundled public Counter site. Android/iOS native execution of this new wrapper remains unverified; compilation and patch checks alone do not prove device behavior.

### Source-generation cost measured in this workspace

With four Counter routes, the cache export held 2,385 gzip payload bytes. Desktop source generation took 0.78 seconds with about 97 MiB maximum resident memory and produced 152 KiB on disk; Mob source generation took 2.22 seconds with about 95 MiB maximum resident memory and produced 1.3 MiB. These are local measurements, not performance guarantees. The existing Mob archive was reused via `MIX_ARCHIVES`; neither run installed dependencies or compiled a native binary. Both generated projects' Elixir sources parsed, and all copied compressed records decoded and matched their routes.
