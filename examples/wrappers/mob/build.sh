#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mix deps.get
mix mob.install
elixir prepare-native.exs
mix mob.deploy --native "$@"
