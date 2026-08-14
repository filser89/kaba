#!/usr/bin/env bash
# Deletes tests skip-marked as REMOVED by a completed feature's test session.
# Runs between features only (session lock must be off). Deterministic: prism-based
# block deletion (delete_removed_examples.rb) + self-verification — the suite must be
# green afterward with the example count reduced by exactly the number deleted, or
# every touched file is rolled back.
#
# Test directory and test command come from config (.kaba/config.yml), same as
# snapshot-tests.sh and session-lock.sh. The deletion engine is
# scripts/ruby/delete_removed_examples.rb, shipped with kaba — ruby-by-necessity:
# it edits RSpec files via Prism AST source ranges (no regex block-guessing), and
# kaba v1 targets Rails/RSpec projects, where ruby is definitionally present
# (prism requires ruby >= 3.3). The `command -v ruby` and helper-existence guards
# below fail loudly if either is missing.
set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/config.sh"

kaba_load_config
HELPER="$SCRIPT_DIR/ruby/delete_removed_examples.rb"
MARKER='skip: "REMOVED by '
RSPEC_TMPFILE=""

cleanup() {
  [[ -n "$RSPEC_TMPFILE" && -f "$RSPEC_TMPFILE" ]] && rm -f "$RSPEC_TMPFILE"
}
trap cleanup EXIT

TEST_BIN="${KABA_TEST_COMMAND%% *}"
command -v jq >/dev/null 2>&1 || kaba_die "jq is required. Install with: brew install jq"
command -v "$TEST_BIN" >/dev/null 2>&1 || kaba_die "$TEST_BIN not found (required to run: $KABA_TEST_COMMAND)"
command -v ruby >/dev/null 2>&1 || kaba_die "ruby not found"
[[ -f "$HELPER" ]] || kaba_die "helper not found: $HELPER"

# Count suite examples via a dry run. Aborts on load errors — a partially loaded
# suite would make the count (and therefore the verification) meaningless.
count_examples() {
  RSPEC_TMPFILE=$(mktemp "${TMPDIR:-/tmp}/rspec-json.XXXXXX")
  (cd "$KABA_REPO_ROOT" && $KABA_TEST_COMMAND --dry-run --format json --out "$RSPEC_TMPFILE" --format progress >/dev/null 2>&1) || true
  [[ -f "$RSPEC_TMPFILE" ]] && jq -e '.examples' "$RSPEC_TMPFILE" >/dev/null 2>&1 \
    || kaba_die "RSpec failed to produce valid JSON (dry run)"
  local errors_outside
  errors_outside=$(jq '.summary.errors_outside_of_examples_count // 0' "$RSPEC_TMPFILE")
  [[ "$errors_outside" -eq 0 ]] || kaba_die "spec files failed to load (errors: $errors_outside) — fix the suite before cleanup"
  jq '.examples | length' "$RSPEC_TMPFILE"
}

# 1. No session may be in flight.
lock_status="$("$SCRIPT_DIR/session-lock.sh" status)"
[[ "$lock_status" == "session-lock: off" ]] || kaba_die "$lock_status — cleanup runs only between features (lock must be off)"

# 2. Clean test tree, so rollback is exact.
[[ -z "$(git -C "$KABA_REPO_ROOT" status --porcelain -- "$KABA_TEST_DIR")" ]] \
  || kaba_die "test directory has uncommitted changes — commit or stash first (rollback must be exact)"

# 3. Find marked files.
marked_files=()
while IFS= read -r f; do marked_files+=("$f"); done \
  < <(grep -rlF "$MARKER" "$KABA_REPO_ROOT/$KABA_TEST_DIR" 2>/dev/null || true)
if [[ ${#marked_files[@]} -eq 0 ]]; then
  echo "[cleanup] nothing to clean — no removal markers found"
  exit 0
fi

# 4. Pre-count.
echo "[cleanup] counting suite examples (dry run)..."
total_before=$(count_examples)

# 5. Delete marked examples.
echo "[cleanup] deleting marked examples in ${#marked_files[@]} file(s)..."
helper_output=$(ruby "$HELPER" "${marked_files[@]}")
echo "$helper_output" | awk -F'\t' '{printf "  %s: %s example(s)\n", $2, $1}'
deleted=$(echo "$helper_output" | awk -F'\t' '{s+=$1} END {print s+0}')
[[ "$deleted" -gt 0 ]] || kaba_die "marker grep matched files but the parser deleted 0 examples — markers malformed?"

# 6. Verify: suite green, count reduced by exactly the number deleted — else roll back.
echo "[cleanup] verifying (full suite run)..."
RSPEC_TMPFILE=$(mktemp "${TMPDIR:-/tmp}/rspec-json.XXXXXX")
rspec_exit=0
(cd "$KABA_REPO_ROOT" && $KABA_TEST_COMMAND --format json --out "$RSPEC_TMPFILE" --format progress) || rspec_exit=$?

rollback() {
  git -C "$KABA_REPO_ROOT" checkout -- "${marked_files[@]}"
  kaba_die "verification failed ($1) — all touched files rolled back"
}

[[ -f "$RSPEC_TMPFILE" ]] && jq -e '.examples' "$RSPEC_TMPFILE" >/dev/null 2>&1 \
  || rollback "suite did not produce valid JSON"
failures=$(jq '.summary.failure_count // 0' "$RSPEC_TMPFILE")
total_after=$(jq '.examples | length' "$RSPEC_TMPFILE")
expected=$((total_before - deleted))
[[ "$failures" -eq 0 ]] || rollback "suite not green: $failures failure(s)"
[[ "$total_after" -eq "$expected" ]] || rollback "example count $total_after, expected $expected ($total_before - $deleted)"

# 7. Report — the human reviews the diff and commits.
echo ""
echo "[cleanup] deleted $deleted example(s); suite green ($total_after examples, was $total_before)"
echo "[cleanup] review the deletion diff:  git diff -- $KABA_TEST_DIR"
