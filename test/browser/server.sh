#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
cd ../../examples/basic
export MIX_ENV=test
exec mix run --no-start ../../scripts/browser-server.exs
