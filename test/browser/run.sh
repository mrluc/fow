#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export NODE_PATH="${FOG_OF_WAR_BROWSER_NODE_MODULES:-$PWD/node_modules}"
(cd ../../examples/basic && MIX_ENV=test mix assets.build)
(cd ../../examples/frontier && MIX_ENV=test mix assets.build)
node "$NODE_PATH/@playwright/test/cli.js" test --config playwright.config.cjs "$@"
