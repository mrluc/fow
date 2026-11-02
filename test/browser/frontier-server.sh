#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../examples/frontier"
export MIX_ENV=test
exec mix run --no-start ../../scripts/frontier-browser-server.exs
