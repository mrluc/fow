# Counters — elixirkit wrapper

Generated from `.fow.json` and an explicitly public HTML bundle. No source Phoenix application, database, credentials or signed LiveView session is embedded. The app serves its read-only public pages at a loopback origin; the real website stays at http://127.0.0.1:47180. Open live site loads that website. This is a starting point, not an authentication implementation.

On macOS with Elixir/OTP, Rust, Tauri CLI and Xcode command-line tools, run `./build.sh`. It fetches deps, packages the small Elixir runtime, generates native icons from the branding source, builds the app and signs it ad hoc for local testing. Production signing/notarization and Windows/Linux release recipes are separate work.

Commit Mix/Cargo/Gradle lockfiles after the first successful build. To preview just the public shell without native compilation, run `mix deps.get` then `mix run --no-start -e 'Application.ensure_all_started(:bandit); {:ok, _} = CountersDesktop.PublicShell.start_link([]); Process.sleep(:infinity)'`. Open the printed PUBLIC_SHELL_READY URL.

`priv/fog_of_war` contains only exported public pages/assets. `priv/fog_of_war_seed.js` seeds missing public snapshots at document start, only for the configured top-frame origin. It never overwrites an existing cached value. Bundled pages use storage at their own origin; the remote website's storage remains separate. The bundled shell handles cold offline opening; remote-origin cold starts, account isolation, OAuth, store review and production signing are separate work.

The inferred/custom `branding/source.*` is converted into native launcher icons during build; a small fallback icon is supplied when no source is available.

The Tauri host uses document-start initialization scripts and permits navigation only between its own loopback origin and the configured site. Remote pages are granted no Tauri IPC capabilities.
