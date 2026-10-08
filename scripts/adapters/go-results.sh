#!/usr/bin/env bash
# Validate a complete Go JSON event stream against source-discovered identities.
set -euo pipefail
HERE="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ $# -eq 3 ]] || { echo 'ERROR: go-results.sh needs inventory, events, and process exit' >&2; exit 1; }
if ! jq -n --slurpfile expected "$1" --slurpfile events "$2" --argjson process_exit "$3" -f "$HERE/go-results.jq"; then
  echo 'ERROR: invalid or incomplete Go test run; fix package/build errors and ensure every expected case executes' >&2
  exit 1
fi
