# Frontier native test host

This ejected development host now starts Frontier through the separate MobWebView bundle API, without wrapper controls. Its historical Counter application name and identifier remain so we can reuse the installed native host and ARM64 build caches. The Counter Phoenix example has not changed. See [native bundle preparation](../../../WRAPPERS.md#native-asset-startup-prototype) for the current output format and repeatable offline test. Prepare an Android Frontier bundle and copy it to `priv/frontier` before deployment; generated bundle files are ignored by Git.

The notes below describe the older generated shell and the independent bridge test. They are retained as history; the current root screen does not use the shell's Live/Offline controls.

## Legacy Counter shell

Generated from `.fow.json` and an explicitly public HTML bundle. No source Phoenix application, database, credentials or signed LiveView session is embedded. The app serves its read-only public pages at a loopback origin; the real website stays at http://127.0.0.1:47180. Open live site loads that website. This is a starting point, not an authentication implementation.

Run `./build.sh --android` or `./build.sh --ios` after installing the corresponding SDK and selecting a device/simulator. The script fetches deps, runs Mob installation, patches document-start preload and deploys the native app. For this development origin on Android, run `adb reverse tcp:47180 tcp:47180` if your site listens on the developer machine at port 47180. Production builds should use a device-reachable HTTPS origin.

Commit Mix/Cargo/Gradle lockfiles after the first successful build. To preview just the public shell without native compilation, run `mix deps.get` then `mix run --no-start -e 'Application.ensure_all_started(:bandit); {:ok, _} = CountersMobile.PublicShell.start_link([]); Process.sleep(:infinity)'`. Open the printed PUBLIC_SHELL_READY URL.

`priv/fog_of_war` contains only exported public pages/assets. `priv/fog_of_war_seed.js` seeds missing public snapshots at document start, only for the configured top-frame origin. It never overwrites an existing cached value. Bundled pages use storage at their own origin; the remote website's storage remains separate. The bundled shell handles cold offline opening; remote-origin cold starts, account isolation, OAuth, store review and production signing are separate work.

The inferred icon is copied to `branding/source.*`. Mobile launchers still use scaffold artwork until applying Mob's documented `mix mob.icon --source` workflow (requires Image).

`prepare-native.exs` patches the pinned Mob WebViews before native build. Reapply after deps.get or seed changes. It replaces marked blocks, checks anchors and refuses unexpected layouts. Android without document-start support retains the offline shell but cannot seed the remote cache before page scripts. Native execution on each device target still needs verification.

## Independent WebView prototype

This development consumer now references the sibling `elixir-client/mob_webview` project through a path dependency and activates its native plugin in `mob.exs`. Its screen uses `MobWebView.view/1`, not the built-in `<WebView>`. Keep the sibling checkout beside `fow`; this prototype is not a published Hex dependency. The server-side FoW package has no dependency on Mob or this component.

The custom component now passes an actual Android ARM64 emulator build and smoke test. The iOS implementation has compiler checks only; its native runtime test is still required. The previously installed native app will not acquire the component through an Elixir-only push. This prototype does not yet add asset serving, document-start FoW snapshot seeding, or cold-offline startup. Its unsigned-plugin acknowledgment is confined to this local example; distributed builds should sign and trust the plugin.


### Verified Android development run

This ejected test host targets only `arm64-v8a` in Gradle and its Zig target map. The installed toolchain produced an invalid 32-bit ARM library during the first all-architecture build; that failure is not fixed or hidden by this ARM64 test. The general generator still retains its upstream target map.

The original Mob scaffold requires `ecto_sqlite3` even for blank apps because its native build compiles the SQLite sources. FoW had dropped that dependency while replacing the scaffold Mix file; it is now retained. The host also retains Mob's development connection startup (which Mob disables for release mode). Long preload strings are generated without Elixir inspect truncation.

```sh
mix mob.deploy --native --android
MOB_WEBVIEW_ANDROID_DEVICE=emulator-5554 \
  mix run --no-start ../../../../mob_webview/test/native/android-smoke.exs
```

The smoke test verifies page load, JavaScript evaluation, a real JS/Elixir round trip, URL updates, Back/Forward/reload, blocked navigation, screen restoration and component cleanup. It uses existing Mob APIs and adds no Mix task. Mob's current launch helpers assume the activity shares the application-id namespace; this host customizes its application id, so the test resolves the correct activity through Android instead.

The **Live** button points to the Counter server on the developer Mac. Start that server and run `adb reverse tcp:47180 tcp:47180` to use it. The bundled public shell and this smoke test run on the device and do not need that reverse connection.
