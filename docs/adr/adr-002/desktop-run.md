# Run Frontier on macOS

The desktop bundle path requires macOS 12 or later. From the FoW checkout, start the example in one terminal:

```sh
cd examples/frontier
source ../../../env.sh
mix phx.server
```

In another terminal, from the FoW checkout, quit any running copy of Frontier and run:

```sh
cd examples/frontier
source ../../../env.sh
mix fow.desktop --force
open "$HOME/Applications/Frontier.app"
```

The task regenerates the icon and app, installs the app in `~/Applications`, and registers it with Spotlight. Press Command–Space and search for **Frontier** to launch it later.

Run the individual steps when iterating on the generated project:

```sh
cd examples/frontier
source ../../../env.sh
mkdir -p .fow
bundle_root=$(mktemp -d "$PWD/.fow/desktop-bundle.XXXXXX")
mix fow.bundle.prepare --platform apple --output "$bundle_root/apple"
mix fow.gen.elixirkit --bundle-dir "$bundle_root/apple" --output .fow/apps/elixirkit/apple --force
bash .fow/apps/elixirkit/apple/build.sh
open -n "$CARGO_TARGET_DIR/release/bundle/macos/Frontier.app"
```

Use the build command alone when editing the generated Rust project. Regenerate after editing the generator or templates. Repeat bundle preparation after changing the example's HTML, JS, CSS, or assets.

For an offline check, quit the app, stop Phoenix, and open the same app again. The startup map and logo should appear and the adjacent bundled routes should work. Select one of those routes and restart Phoenix to watch the desktop app reconnect there.

The smoke test used Frontier's HTTP loopback origin. The native HTTPS custom-scheme image and filter behavior was measured separately in the probes in this directory.
