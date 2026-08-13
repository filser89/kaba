#!/usr/bin/env bash
# Runs every test/*_test.sh and prints a summary. Exit 1 if any assertion failed.
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

total_pass=0
total_fail=0

for f in "$SCRIPT_DIR"/*_test.sh; do
  [ -e "$f" ] || continue
  printf '%s\n' "$(basename "$f")"
  # Each file runs in its own process; counters come back on the last line.
  counts="$(
    KABA_TEST_PASS=0 KABA_TEST_FAIL=0
    export KABA_TEST_PASS KABA_TEST_FAIL
    bash -c '
      . "$1" || exit 1
      printf "__COUNTS__ %s %s\n" "$KABA_TEST_PASS" "$KABA_TEST_FAIL"
    ' _ "$f" | tee /dev/stderr | grep '^__COUNTS__' || true
  )"
  # A file that crashes (syntax error, stray exit) never prints __COUNTS__.
  # That is a failure, not a zero — a dead test file must never read as green.
  if [ -z "$counts" ]; then
    printf '  %-58s FAIL\n' "$(basename "$f") crashed before reporting"
    total_fail=$((total_fail + 1))
    continue
  fi
  p="$(printf '%s' "$counts" | awk '{print $2}')"
  fl="$(printf '%s' "$counts" | awk '{print $3}')"
  total_pass=$((total_pass + ${p:-0}))
  total_fail=$((total_fail + ${fl:-0}))
done

printf '\n%s passed, %s failed\n' "$total_pass" "$total_fail"
[ "$total_fail" -eq 0 ]
