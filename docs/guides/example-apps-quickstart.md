# Quickstart: run the example apps

| Counters | Frontier |
| --- | --- |
| ![Counters index](screenshots/counters.jpg) | ![Frontier multiplayer map](screenshots/frontier.jpg) |

## Prerequisites

- Git and access to the FoW repository. Clone it and enter the checkout:

  ```sh
  git clone git@github.com:mrluc/fow.git
  cd fow
  ```
- Elixir 1.20.4 and Erlang/OTP 29.0.6, as pinned in `.tool-versions`. Run `mix local.hex` from the checkout if Hex is missing.
- For macOS builds, install Rust and the Xcode command-line tools. The generated build runs `cargo tauri`. If `cargo tauri --version` fails, install it once with `cargo install tauri-cli --version '^2' --locked`. Both Cargo commands can run from any directory.
- For Android builds, install Android Studio, its Android SDK and Platform Tools, and start an emulator visible in `adb devices`. From the FoW checkout, run `mix archive.install hex mob_new` once to install the Mix generator. The generated app fetches the public WebView dependency over HTTPS.


## Example: Counters app

Counters has three routes with increment buttons. Visit One, increment it, and return to the list. Open the Fog of War panel and pause the socket. One still opens at the saved value, and its increment button is disabled. Three stays unavailable until you visit it online. The Cache tab shows the saved route and its payload. Resume the socket to use the counter again.

![Counters offline with the DevTools cache open](screenshots/counters-offline.jpg)

The integration is in these files under `examples/basic/`:

- `mix.exs` adds the checkout as a path dependency.
- `assets/js/app.js` registers the FoW hook and installs the coordinator before connecting LiveSocket.
- `lib/fog_of_war_basic_web/components/layouts.ex` wraps routed content with `FogOfWar.region` and renders `FogOfWar.dev_tools`.
- `.fow.json` makes the index the startup document and preloads One and Two in native builds. `config/dev.exs` enables the DevTools locally.

### Run Counters locally

From the repository root:

```sh
cd examples/basic
mix setup
mix phx.server
```

Open [the local Counters demo](http://127.0.0.1:47180/). Keep Phoenix running for the following builds.

### Build and run Counters on macOS

In a second terminal, from `examples/basic`:

```sh
mix fow.desktop
open "$HOME/Applications/Counters.app"
```

Use `mix fow.desktop --force` to rebuild and replace a previous generated project and installed copy.

### Build and run Counters on Android

From `examples/basic`, with one emulator selected by adb:

```sh
mix fow.bundle.prepare --env android-dev --platform android
mix fow.gen.mobile --env android-dev
cd .fow/android-dev/projects/mobile
adb reverse tcp:47180 tcp:47180
./build.sh --android
adb shell am start -W -n dev.fogofwar.counters/com.example.counters_mobile.MainActivity
```

Open the generated `android/` subdirectory in Android Studio to inspect the project. Move an existing generated bundle aside before repeating bundle preparation. Pass `--force` to the generator to replace its output.

## Example: Frontier multiplayer app

Frontier is an isometric multiplayer game. Move around online to explore, then toggle offline and revisit explored squares. Reconnect to resume the game. The native bundle ships the startup document and its artwork.

### Run Frontier locally

From the repository root:

```sh
cd examples/frontier
mix setup
mix phx.server
```

Open [the local Frontier demo](http://127.0.0.1:47190/multi/lat/0/lon/0). Keep Phoenix running for the following builds.

### Build and run Frontier on macOS

In a second terminal, from `examples/frontier`:

```sh
mix fow.desktop
open "$HOME/Applications/Frontier.app"
```

Use `mix fow.desktop --force` to rebuild and replace a previous generated project and installed copy.

### Build and run Frontier on Android

From `examples/frontier`, with one emulator selected by adb:

```sh
mix fow.bundle.prepare --env android-dev --platform android
mix fow.gen.mobile --env android-dev
cd .fow/android-dev/projects/mobile
adb reverse tcp:47190 tcp:47190
./build.sh --android
adb shell am start -W -n dev.fogofwar.frontier/com.example.frontier_mobile.MainActivity
```

Open the generated `android/` subdirectory in Android Studio to inspect the project. Move an existing generated bundle aside before repeating bundle preparation. Pass `--force` to the generator to replace its output.
