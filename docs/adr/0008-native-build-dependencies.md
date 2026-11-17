# Native build dependencies

Status: proposed

FoW generates a native host around an existing Phoenix app. We want a clean
checkout to have a short path to a runnable app, and generated projects to
remain buildable after they leave the FoW checkout.

## What happens today

- The macOS generator writes the Tauri host. Its build script invokes
  `cargo tauri icon` and `cargo tauri build`. The ElixirKit dependency does
  not provide the Cargo command.
- The mobile generator invokes `mix mob.new`. That task comes from the
  separately installed `mob_new` Mix archive. The generated host's Mob
  dependency serves a different purpose and is resolved after scaffolding.
- The generated host fetches FoW's WebView plugin at a fixed Git commit.
  The SSH URL currently requires a GitHub account with repository access.

## Proposed defaults

Keep OS SDKs, signing tools and Rust as developer prerequisites. Give native
commands an early check that prints the exact missing tool and install command.
For Tauri and the Mob archive, start with an explicit setup step if we can
install or validate a pinned version. Avoid silently changing the user's
global Cargo binaries or Mix archives during generation. Revisit a project
local tool install once we know how to run it both from FoW and from an ejected
project.

Keep the Mob scaffold upstream. If Mob offers a supported generator API that
can be called as a dependency, prefer it over invoking a global archive.
Vendoring templates would remove the archive requirement but leave FoW
responsible for keeping the native scaffold in sync.

Once the WebView repo is public, switch generated projects to a pinned HTTPS
Git dependency. This makes ordinary builds credential-free. Keep the local
checkout override in contributor documentation. Consider a versioned Hex
dependency once the plugin's native sources and registration metadata have
been verified from a Hex package in a clean build.

Before changing defaults, generate both sample apps from a clean environment,
build the hosts, and verify that an ejected project can build on its own.
