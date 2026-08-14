#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
C="$SCRIPT_DIR/../commands"

EXPECTED="acceptance-criteria architecture architecture-diff clarify \
fix-tests implement-code implement-tests init plan-code \
plan-tests research review-tests specify"

for name in $EXPECTED; do
  assert_file_exists "$name.md exists" "$C/$name.md"
done

assert_eq "exactly 13 commands" "13" "$(ls "$C"/*.md | wc -l | tr -d ' ')"

for f in "$C"/*.md; do
  b="$(basename "$f")"
  # grep exits 1 on no match — absence of the name means expecting exit 1.
  assert_fail "$b has no 'speckit'"        1 grep -qi "speckit"          "$f"
  assert_fail "$b has no '.specify'"       1 grep -q  "\.specify"        "$f"
  assert_fail "$b has no extensions.yml"   1 grep -q  "extensions\.yml"  "$f"
  assert_fail "$b has no 'constitution'"   1 grep -qi "constitution"     "$f"
  assert_fail "$b has no 'specs/' feature dir" 1 grep -q "specs/"        "$f"
  assert_stdout_match "$b has frontmatter" '^---$' head -1 "$f"
done
