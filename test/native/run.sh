#!/usr/bin/env bash
# Real macOS ElixirKit/Tauri/WKWebView smoke test; uses the existing native build cache.
set -euo pipefail
cd "$(dirname "$0")/../.."
source ../env.sh
if [ "$(uname -s)" != Darwin ]; then echo 'This native check requires macOS.' >&2; exit 1; fi
if curl -fsS http://127.0.0.1:47183/ >/dev/null 2>&1; then echo 'Stop the browser test servers before running the native test.' >&2; exit 1; fi
mkdir -p .fow/native-test
(cd examples/basic && MIX_ENV=test mix assets.build)
bash test/browser/server.sh >.fow/native-test/server.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
for attempt in {1..100}; do
  if curl -fsS http://127.0.0.1:47183/ >/dev/null 2>&1; then break; fi
  if ! kill -0 "$server_pid" 2>/dev/null; then cat .fow/native-test/server.log; exit 1; fi
  sleep 0.1
done
python3 - <<'PY'
import json, pathlib, shutil
root=pathlib.Path.cwd()
manifest=json.loads((root/'examples/basic/.fow.json').read_text())
manifest['web']['origin']='http://127.0.0.1:47182'
(root/'.fow/native-test/manifest.json').write_text(json.dumps(manifest))
# Only test-owned generated files are replaced. Reuse downloaded dependencies, not a native toolchain copy.
project=root/'.fow/native-test/desktop'
shutil.rmtree(project,ignore_errors=True)
shutil.copytree(root/'examples/wrappers/elixirkit',project,ignore=shutil.ignore_patterns('_build','deps','target','.DS_Store'))
(project/'deps').symlink_to(root/'examples/wrappers/elixirkit/deps',target_is_directory=True)
shutil.rmtree(root/'.fow/native-test/cache',ignore_errors=True)
PY
(cd examples/basic && MIX_ENV=test mix fow.export.cache --manifest ../../.fow/native-test/manifest.json --env dev --output ../../.fow/native-test/cache)
node test/native/desktop-smoke.cjs
