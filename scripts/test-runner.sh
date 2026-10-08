#!/usr/bin/env bash
# Runner-neutral operations. JSON goes to stdout; diagnostics go to stderr.
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/config.sh"

operation="${1:-}"
case "$operation" in
  --help|-h|'') echo 'Usage: test-runner.sh run|identities|digests --phase baseline|post-test|post-impl|cleanup'; exit 0 ;;
  run|identities|digests) shift ;;
  *) kaba_die "unknown runner operation: $operation" ;;
esac
phase=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) [[ $# -gt 1 ]] || kaba_die '--phase needs a value'; phase="$2"; shift 2 ;;
    *) kaba_die "unknown runner option: $1" ;;
  esac
done
case "$phase" in baseline|post-test|post-impl|cleanup) ;; *) kaba_die 'an explicit valid --phase is required' ;; esac
command -v jq >/dev/null 2>&1 || kaba_die 'jq is required'
kaba_load_config

RSPEC_TMPFILE=""
DIGEST_TMPFILE=""
KABA_GO_TMPDIR=""
cleanup() {
  [[ -z "$RSPEC_TMPFILE" ]] || rm -f "$RSPEC_TMPFILE"
  [[ -z "$DIGEST_TMPFILE" ]] || rm -f "$DIGEST_TMPFILE"
  [[ -z "$KABA_GO_TMPDIR" ]] || rm -rf "$KABA_GO_TMPDIR"
  return 0
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
require_test_command() {
  local bin="${KABA_TEST_COMMAND%% *}"
  command -v "$bin" >/dev/null 2>&1 || kaba_die "$bin not found (required to run: $KABA_TEST_COMMAND)"
}
case "${KABA_TEST_RUNNER:-rspec}" in
  rspec)
    . "$SCRIPT_DIR/adapters/rspec.sh"
    if [[ "$operation" == run ]]; then run_rspec_json false >&2; else run_rspec_json true; fi
    if [[ "$operation" == identities ]]; then
      jq '{runner:"rspec",schema:1,context:{},examples:[.examples[] | {id,full_description,file_path,line_number}]}' "$RSPEC_TMPFILE"
    else
      run_digest_pass
      jq --rawfile digests "$DIGEST_TMPFILE" '
        ($digests | split("\n") | map(select(length > 0) | split("\t") | {key:(.[0]+":"+.[1]),value:.[2]}) | from_entries) as $dmap |
        {runner:"rspec",schema:1,context:{},examples:[.examples[] | {id,full_description,file_path,line_number,status,digest:($dmap[(.file_path+":"+(.line_number|tostring))] // null)}]}' "$RSPEC_TMPFILE"
    fi ;;
  go)
    . "$SCRIPT_DIR/adapters/go.sh"
    kaba_go_operation "$operation" "$phase" ;;
  *) kaba_die "unsupported test runner: $KABA_TEST_RUNNER" ;;
esac
