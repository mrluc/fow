# Counters — mob wrapper

Generated from `.fow.json` and an explicitly public HTML bundle. No source Phoenix application, database, credentials or signed LiveView session is embedded. The app serves its read-only public pages at a loopback origin; the real website stays at http://127.0.0.1:47180. Open live site loads that website. This is a starting point, not an authentication implementation.

Run `./build.sh --android` or `./build.sh --ios` after installing the corresponding SDK and selecting a device/simulator. The script fetches deps, runs Mob installation, patches document-start preload and deploys the native app. For this development origin on Android, run `adb reverse tcp:47180 tcp:47180` if your site listens on the developer machine at port 47180. Production builds should use a device-reachable HTTPS origin.

Commit Mix/Cargo/Gradle lockfiles after the first successful build. To preview just the public shell without native compilation, run `mix deps.get` then `mix run --no-start -e 'Application.ensure_all_started(:bandit); {:ok, _} = CountersMobile.PublicShell.start_link([]); Process.sleep(:infinity)'`. Open the printed PUBLIC_SHELL_READY URL.

`priv/fog_of_war` contains only exported public pages/assets. `priv/fog_of_war_seed.js` seeds missing public snapshots at document start, only for the configured top-frame origin. It never overwrites an existing cached value. Bundled pages use storage at their own origin; the remote website's storage remains separate. The bundled shell handles cold offline opening; remote-origin cold starts, account isolation, OAuth, store review and production signing are separate work.

The inferred icon is copied to `branding/source.*`. Mobile launchers still use scaffold artwork until applying Mob's documented `mix mob.icon --source` workflow (requires Image).

`prepare-native.exs` patches the pinned Mob WebViews before native build. Reapply after deps.get or seed changes. It replaces marked blocks, checks anchors and refuses unexpected layouts. Android without document-start support retains the offline shell but cannot seed the remote cache before page scripts. Native execution on each device target still needs verification.

## Independent WebView prototype

This development consumer now references the sibling `elixir-client/mob_webview` project through a path dependency and activates its native plugin in `mob.exs`. Its screen uses `MobWebView.view/1`, not the built-in `<WebView>`. Keep the sibling checkout beside `fow`; this prototype is not a published Hex dependency. The server-side FoW package has no dependency on Mob or this component.

The plugin's Swift/Kotlin source and Elixir integration compile, but a mobile native rebuild and device/simulator smoke test are still required. The previously installed native app will not acquire the component through an Elixir-only push. This prototype does not yet add asset serving, document-start FoW snapshot seeding, or cold-offline startup. Its unsigned-plugin acknowledgment is confined to this local example; distributed builds should sign and trust the plugin.
