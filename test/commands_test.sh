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

# --- F-1: the prior-run gate ------------------------------------------------------
# Positive, negative, and count must all agree, so adding a gate without updating this
# list (or vice versa) fails rather than drifting.
GATED="specify acceptance-criteria plan-tests plan-code implement-tests implement-code"
UNGATED="architecture architecture-diff clarify fix-tests init research review-tests"

for name in $GATED; do
  assert_ok "$name calls check-artifacts.sh"          grep -q 'check-artifacts\.sh' "$C/$name.md"
  assert_ok "$name passes its own command name"       grep -q "check-artifacts\.sh $name" "$C/$name.md"
  assert_ok "$name fails closed on a missing answer"  grep -qi 'never "no' "$C/$name.md"
  assert_ok "$name ends the turn after asking"        grep -qi 'end your turn' "$C/$name.md"
done

for name in $UNGATED; do
  assert_fail "$name is deliberately ungated" 1 grep -q 'check-artifacts\.sh' "$C/$name.md"
done

assert_eq "exactly 6 gated commands" "6" \
  "$(grep -l 'check-artifacts\.sh' "$C"/*.md | wc -l | tr -d ' ')"

# Presence proves nothing about ordering, and ordering is the requirement: the gate
# must precede any token-expensive work, not merely the write.
line_of() { grep -n "$2" "$1" | head -1 | cut -d: -f1; }

for name in acceptance-criteria plan-tests plan-code implement-tests implement-code; do
  g="$(line_of "$C/$name.md" 'check-artifacts\.sh')"
  w="$(line_of "$C/$name.md" 'Load context\|Read the spec\|read the \*\*locked test suite\*\*\|Read the acceptance criteria\|Arm the session lock')"
  assert_ok "$name gates before its first expensive step" test "$g" -lt "$w"
done

# specify's hazard is new-feature.sh creating a stray branch, so the gate precedes it.
# Match the invocation, not the prose mentions (the frontmatter names it too).
gs="$(line_of "$C/specify.md" 'check-artifacts\.sh')"
ns="$(line_of "$C/specify.md" 'kaba\.scriptdir)/new-feature\.sh')"
assert_ok "specify gates before new-feature.sh" test "$gs" -lt "$ns"

# clarify's exception: it must NOT gate on its output existing, only on a settled spec.
assert_fail "clarify does not call check-artifacts.sh" 1 grep -q 'check-artifacts\.sh' "$C/clarify.md"
assert_ok   "clarify gates on a settled spec instead"  grep -qi 'no open questions and no unconfirmed decisions' "$C/clarify.md"
assert_ok   "clarify ends the turn after asking"       grep -qi 'end your turn' "$C/clarify.md"
