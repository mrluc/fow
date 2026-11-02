#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [ "$(uname -s)" != Darwin ]; then echo "This first release recipe requires macOS." >&2; exit 1; fi
mix deps.get
MIX_ENV=prod mix release counters_desktop --overwrite --path src-tauri/target/rel
icons=(branding/source.*)
if [ ! -f "${icons[0]}" ]; then icons=(branding/fallback.png); fi
if [ -f "${CLIENT_TAURI_JS:-}" ]; then
  node "$CLIENT_TAURI_JS" icon "${icons[0]}" --fit contain --output src-tauri/icons
  node "$CLIENT_TAURI_JS" build --bundles app --ci
else
  cargo tauri icon "${icons[0]}" --fit contain --output src-tauri/icons
  cargo tauri build --bundles app --ci
fi
bundle_name='Counters.app'
codesign --force --deep --sign - "${CARGO_TARGET_DIR:-$PWD/src-tauri/target}/release/bundle/macos/$bundle_name"
