#!/usr/bin/env bash
set -euo pipefail
# Compatibility entry point: never allow callers to override the selected environment.
for arg in "$@"; do
  case "$arg" in --env|--env=*) echo 'destroy-dev.sh does not accept --env' >&2; exit 1 ;; esac
done
exec bash "$(dirname "${BASH_SOURCE[0]}")/destroy-env.sh" --env dev "$@"
