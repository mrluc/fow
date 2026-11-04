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

### Generate source without native compilation

Desktop generation still uses the legacy full export. Mobile generation now uses the prepared executable bundles and the separate Mob WebView plugin:

```sh
mix fow.export --env dev
mix fow.gen.elixirkit --env dev

mix fow.bundle.prepare --env dev --platform android
mix fow.bundle.prepare --env dev --platform ios
mix fow.gen.mob --env dev
```

Prepare only the platforms listed in `mob.platforms`; omitted `mob.platforms` defaults to Android and iOS. Mobile inputs live under `.fow/native/<env>/<platform>`, with `.fow/native/default` used for old flat manifests without an environment. `--bundle-dir` selects another parent folder containing the platform folders. The mobile generator copies only files declared in each native allowlist, rejects an environment/origin/public-path mismatch, and preserves separate Android and Apple startup/asset representations. Its generated screen loads the matching platform bundle at the real website URL. FoW's browser code imports the gzip records into IndexedDB in batches before using them for offline navigation.

The WebView defaults to the dedicated repository `git@github.com:mrluc/fow_webview_mob.git`, pinned to a full commit in the generated `mix.exs`. It is private during development, so builders need SSH access. For local WebView development use `--webview-path /absolute/path/to/mob_webview`. To choose another repository use `--webview-git URL --webview-ref FULL_COMMIT_SHA`. The same source can be set in the manifest as `mob.webview: {"path": "../mob_webview"}` or `mob.webview: {"git": "git@github.com:owner/repo.git", "ref": "full commit SHA"}`; paths resolve relative to the manifest. A local path and a Git source are mutually exclusive. Once the repository is public, `--webview-git https://github.com/mrluc/fow_webview_mob.git --webview-ref 1be07da3604a64bc6ef11c87858c3c9ad372e80b` allows an HTTPS source. No unpublished Hex version is assumed.

These commands generate source; they do not compile SDK/native binaries. The generated Mob project activates the WebView plugin and explicitly acknowledges the inspected unsigned prototype. Production distribution should sign and trust it. Android cold-offline startup and recovery are device-tested; the Apple implementation still has SDK compile checks only.

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

Both tasks accept `--manifest path/to/.fow.json`. They refuse existing output folders unless `--force` is passed. With `--force`, the entire old output is replaced only after generation succeeds in a temporary sibling directory; custom changes and downloaded/build dependencies in that output are discarded. Source-project, home/root/ancestor and symlink destinations are rejected. The manifest's bundle path is resolved relative to its own directory; output paths are relative to the command's working directory. Generated applications are independent projects and do not depend on `:fow` or the source Phoenix app. Commit the new hosts and their lockfiles after resolving/building them.

The Mob generator requires the upstream `mob_new` archive once (`mix archive.install hex mob_new`). It invokes `mix mob.new --blank --no-install` internally and writes the seamless wrapper screen, startup and build script. Native WebView registration and asset serving belong to the separate plugin; no built-in Mob WebView patch is generated. Users do not run the scaffold generator or write WebView bridge code for each site. ElixirKit generation writes its small Tauri host directly; no Tauri scaffold generator is needed.

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

The mobile script fetches dependencies, runs Mob's installation step and invokes Mob's native deployment with the WebView plugin. It needs Android SDK/NDK/JDK or Xcode and a compatible simulator/device. Installation can download large OTP runtimes. The icon source is copied to `branding/source.*`; mobile launchers retain Mob's default artwork until applying it with Mob's documented `mix mob.icon` workflow (requires its Image dependency). Desktop artwork is applied by the generated build script.

For this workspace's running Counter demo, the manifest uses `http://127.0.0.1:47180`. Android needs `adb reverse tcp:47180 tcp:47180` to reach the developer machine at that address. Distribution should use a reachable HTTPS origin. The bundled shell works independently of that connection.

## Build, install, or run the whole desktop workflow

From the Phoenix app containing `.fow.json`:

```sh
# Source generation only. --output always names the generated source project.
mix fow.gen.elixirkit --env dev --output native/desktop --force

# Build that project; uses its build.sh and your configured native toolchain.
mix fow.build.elixirkit --env dev --output native/desktop

# Install an already-built app, without rebuilding or launching it.
mix fow.install.osx-local --app /path/to/Counter.app --force

# Refresh public export, generate sources, build, and install in one command.
mix fow.desktop --env dev --force
```

`fow.desktop` is macOS-only. Its `--force` replaces the selected public export, generated source project and installed app. Each replacement is staged before swapping; a failed generation or app copy leaves the previous destination intact. It does not roll back a successful export/generation if a later native build fails. Run without `--force` to preserve existing outputs. `--manifest`, `--env`, `--output` and `--base-url` select the manifest/environment, generated source destination and optional capture server. The normal manifest `web.origin` remains the website identity.

`fow.install.osx-local` copies into `~/Applications` by default; `--applications /other/directory` changes that directory. It registers the installed bundle with LaunchServices and asks Spotlight to import it. It does not open the app, publish it, or add distribution signing/notarization. The conventional underscore spelling `fow.install.osx_local` works too.

For an ejected project, generate into a permanent directory, commit it and customize it. Continue using its `build.sh` or point `fow.build.elixirkit --output` at it. Do not use `--force` on that project unless you intend to discard all of its modifications. Mobile generation supports the same atomic `--force`; mobile build/deploy still uses the generated `build.sh --android` / `--ios` until separate strategies are added.

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


The client now exposes `coordinator.cache.importBundle(indexURL, options)` for these gzip files. It imports into IndexedDB in resumable batches and preserves compatible device captures. See the README for the API and native `readAsset` bridge. The generated wrappers still use their older startup/seed mechanism; automatic native-host integration is a separate step. The macOS native smoke test exercises the new importer in an actual ElixirKit/Tauri WebView without claiming that the production generator already performs that integration.

### Direct desktop launch

Set `elixirkit.startup` to `"live"` to open `web.origin + web.start_path` directly in the desktop window. The default `"bundled"` retains the earlier public-shell prototype. Direct launch needs the configured server to be reachable at startup; it does not implement the bundled-first automatic recovery described in the ADR. Frontier's `.fow.json` demonstrates this development configuration. Desktop builds now explicitly include the generated `.icns` and PNG files in their bundle icon configuration.

## Native asset startup prototype

`mix fow.bundle.prepare --platform android` reads the selected manifest environment, fetches each explicit public path and prepares `.fow/native/<environment>/android/`. Use `--platform ios` for the Apple variant. `--output` selects a fresh destination; existing destinations are refused. `--debug` retains the capture HTML. This task requires Elixir, the selected website and its matching local static directory; it does not require Playwright or a running production configuration on the build machine.

The output contains executable `startup.html`, metadata-only `index.json`, separate gzip region files, copied assets, a small startup configuration script and `native.json`, the native resource allowlist. Application scripts are included. HTML URL attributes and CSS asset references are rewritten for Apple's custom asset scheme; navigation URLs, the cache origin and LiveView tokens retain their real website values. Each region is processed separately. This prototype supports local allowlisted static files, including CSS imports; it does not discover arbitrary dynamic imports or arbitrary URLs constructed inside JavaScript. Frontier explicitly resolves its canvas sprite URLs through the startup asset map. Remote CDN assets and additional HTML asset forms need their own coverage before using this as a general exporter.

The separate `mob_webview` package accepts `bundle: MobWebView.Bundle.load!(root)` alongside `url: bundle["url"]`. Copy the prepared directory to the generated host's `priv` directory and resolve its on-device application path. Native code reads only declared files. The initial document is supplied once; later document navigations reach the website, allowing LiveView to renew stale bootstrap state. The existing gzip importer seeds IndexedDB in batches and preserves newer device captures. A small startup configuration is present in the HTML, not the region payloads.

The existing ejected Android test host in `examples/wrappers/mob` now opens `CountersMobile.FrontierScreen` without native Live/Offline buttons or the legacy shell. Its historical application identifier stays unchanged so the installed ARM64 build can be reused. The Counter Phoenix example is unchanged. The general mobile generator now emits this same bundle API and seamless screen, with a bundle per selected platform.

After preparing an Android bundle and copying it to that host's `priv/frontier`, deploy with Mob's existing native deployment command. Run the repeatable device test from the host:

```sh
MOB_WEBVIEW_ANDROID_DEVICE=emulator-5554 mix run --no-start ../../../test/native/mob-frontier.exs
```

The test clears only the development host's WebView data, starts without website port forwarding, checks four imported routes, decodes all five artwork files, reads their pixels through canvas, verifies the pixel fog paints, and navigates offline. It then restores forwarding and requires automatic recovery on the selected route followed by another live navigation. Remove any existing website forwarding before running it. `test/browser/native-bundle.spec.cjs` repeats this flow in a clean browser context using the real bundle exporter.

Android ARM64 emulator execution passed. Apple source passes the installed iOS SDK typecheck only: `WKURLSchemeHandler` serves assets and `loadSimulatedRequest` supplies the initial document at its real URL, requiring iOS 15 or newer. Custom-scheme fetch, storage, canvas and connection behavior remain unverified on an iOS runtime. No Apple simulator was downloaded. Neither platform currently guarantees content preservation if a recovery HTTP navigation fails after the socket reconnects, and this prototype does not cache assets first discovered during later online browsing.
