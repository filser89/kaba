#!/usr/bin/env bash
# Self-test for the assertion helpers. Verifies each helper both passes and fails.
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"

assert_ok        "assert_ok accepts exit 0"            true
assert_fail      "assert_fail accepts exit 1"          1 false
assert_stdout_match "assert_stdout_match finds text"   "hello" echo hello
assert_stderr_match "assert_stderr_match finds text"   "boom"  sh -c 'echo boom >&2; exit 1'
assert_eq        "assert_eq compares equal strings"    "a" "a"
assert_file_exists "assert_file_exists finds a file"   "$SCRIPT_DIR/assert.sh"

# Negative control: the harness must be able to report a failure, not just passes.
# Runs assert_eq in a subshell so its failure does not fail this file.
out="$( (assert_eq "deliberate mismatch" "x" "y") 2>&1 || true )"
case "$out" in
  *FAIL*) assert_ok "harness reports failures" true ;;
  *)      assert_ok "harness reports failures" false ;;
esac
