#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
export GOCACHE="${GOCACHE:-${TMPDIR:-/tmp}/kaba-go-build}"
assert_ok "Go helper unit tests" bash -c 'cd "$1/scripts/go" && go test ./...' _ "$SCRIPT_DIR/.."
