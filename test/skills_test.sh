#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
S="$SCRIPT_DIR/../skills"

EXPECTED="acceptance-criteria architecture architecture-diff clarify \
fix-tests implement-code implement-tests init plan-code \
plan-tests research review-tests specify"

# The per-skill matrix is driven by EXPECTED, never by a "$S"/*/SKILL.md glob. A skill
# directory that lost its SKILL.md drops out of a glob silently, leaving a green suite
# with that skill unchecked; driven from the name list it fails instead. `checked`
# proves the loop actually ran the full matrix rather than skipping into a pass.
checked=0
for name in $EXPECTED; do
  f="$S/$name/SKILL.md"
  assert_file_exists "$name/SKILL.md exists" "$f"
  [ -f "$f" ] || continue
  checked=$((checked + 1))

  # grep exits 1 on no match — absence of the name means expecting exit 1.
  assert_fail "$name has no 'speckit'"        1 grep -qi "speckit"          "$f"
  assert_fail "$name has no '.specify'"       1 grep -q  "\.specify"        "$f"
  assert_fail "$name has no extensions.yml"   1 grep -q  "extensions\.yml"  "$f"
  assert_fail "$name has no 'constitution'"   1 grep -qi "constitution"     "$f"
  assert_fail "$name has no 'specs/' feature dir" 1 grep -q "specs/"        "$f"
  assert_stdout_match "$name has frontmatter" '^---$' head -1 "$f"

  # Invocation namespaces off the directory name, so a `name:` that disagrees with the
  # directory is a lie in the manifest even though /kaba:<dir> keeps working.
  assert_ok "$name declares name: matching its directory" \
    grep -qx "name: $name" "$f"

  # The pipeline is a chain of human gates, and implement-tests/implement-code arm and
  # clear the session lock — a model that fires one on its own can disarm the two-session
  # boundary. Asserted against the frontmatter block only: the key is inert in prose.
  assert_stdout_match "$name blocks model invocation" '^disable-model-invocation: true$' \
    awk 'NR>1 && /^---$/{exit} NR>1{print}' "$f"

  # `handoffs:` is a VS Code custom-agents key, inert in Claude Code — inherited from
  # spec-kit's multi-target templates. It must not come back: it reads as working
  # next-step wiring while doing nothing at all.
  assert_fail "$name carries no inert handoffs: key" 1 grep -q '^handoffs:' "$f"

  # Every template read must route through the pinned script dir. A file-relative
  # ../templates would resolve against the skill directory and break the moment the
  # layout moves again — which is exactly what this migration just did.
  assert_eq "$name routes ../templates through kaba.scriptdir" \
    "$(grep -o '\.\./templates' "$f" | wc -l | tr -d ' ')" \
    "$(grep -o 'kaba\.scriptdir)/\.\./templates' "$f" | wc -l | tr -d ' ')"
done

assert_eq "every expected skill was checked" "13" "$checked"
assert_eq "exactly 13 skill directories" "13" \
  "$(ls -d "$S"/*/ | wc -l | tr -d ' ')"

# --- next-step guidance ------------------------------------------------------------
# Deleting the inert `handoffs:` blocks would otherwise leave ten of thirteen skills
# ending on nothing. Ten now carry a `## Next Step` section; the three below already
# said it in prose and keep saying it where they said it.
SECTIONED="acceptance-criteria architecture architecture-diff clarify implement-code \
implement-tests plan-code plan-tests research review-tests"
INLINE="fix-tests init specify"

assert_eq "sectioned + inline covers every skill" \
  "$(printf '%s\n' $EXPECTED | sort | tr '\n' ' ')" \
  "$(printf '%s\n' $SECTIONED $INLINE | sort | tr '\n' ' ')"

for name in $SECTIONED; do
  assert_ok "$name has a Next Step section" grep -qx '## Next Step' "$S/$name/SKILL.md"
done

# init and specify point at their successor from the report step. fix-tests deliberately
# has no automatic successor — the human decides when to re-run review (Key Rule 8) — so
# it is asserted to keep saying that rather than to name a next command.
assert_ok "init points at specify"       grep -q 'kaba:specify.*next step'  "$S/init/SKILL.md"
assert_ok "specify points at clarify"    grep -q 'kaba:clarify.*next step'  "$S/specify/SKILL.md"
assert_ok "fix-tests declines a handoff" grep -qi 'no automatic handoff'    "$S/fix-tests/SKILL.md"

# --- F-1: the prior-run gate ------------------------------------------------------
# Positive, negative, and count must all agree, so adding a gate without updating this
# list (or vice versa) fails rather than drifting.
GATED="specify acceptance-criteria plan-tests plan-code implement-tests implement-code"
UNGATED="architecture architecture-diff clarify fix-tests init research review-tests"

# The two lists must partition EXPECTED — otherwise a new skill could be absent from
# both and never be judged either way.
assert_eq "gated + ungated covers every skill" \
  "$(printf '%s\n' $EXPECTED | sort | tr '\n' ' ')" \
  "$(printf '%s\n' $GATED $UNGATED | sort | tr '\n' ' ')"

gated_count=0
for name in $GATED; do
  f="$S/$name/SKILL.md"
  gated_count=$((gated_count + 1))
  assert_ok "$name calls check-artifacts.sh"          grep -q 'check-artifacts\.sh' "$f"
  assert_ok "$name passes its own skill name"         grep -q "check-artifacts\.sh $name" "$f"
  assert_ok "$name fails closed on a missing answer"  grep -qi 'never "no' "$f"
  assert_ok "$name ends the turn after asking"        grep -qi 'end your turn' "$f"
done

for name in $UNGATED; do
  assert_fail "$name is deliberately ungated" 1 grep -q 'check-artifacts\.sh' "$S/$name/SKILL.md"
done

assert_eq "exactly 6 gated skills" "6" "$gated_count"

# Presence proves nothing about ordering, and ordering is the requirement: the gate
# must precede any token-expensive work, not merely the write.
line_of() { grep -n "$2" "$1" | head -1 | cut -d: -f1; }

for name in acceptance-criteria plan-tests plan-code implement-tests implement-code; do
  g="$(line_of "$S/$name/SKILL.md" 'check-artifacts\.sh')"
  w="$(line_of "$S/$name/SKILL.md" 'Load context\|Read the spec\|read the \*\*locked test suite\*\*\|Read the acceptance criteria\|Arm the session lock')"
  assert_ok "$name gates before its first expensive step" test "$g" -lt "$w"
done

# specify's hazard is new-feature.sh creating a stray branch, so the gate precedes it.
# Match the invocation, not the prose mentions (the frontmatter names it too).
gs="$(line_of "$S/specify/SKILL.md" 'check-artifacts\.sh')"
ns="$(line_of "$S/specify/SKILL.md" 'kaba\.scriptdir)/new-feature\.sh')"
assert_ok "specify gates before new-feature.sh" test "$gs" -lt "$ns"

# clarify's exception: it must NOT gate on its output existing, only on a settled spec.
assert_fail "clarify does not call check-artifacts.sh" 1 grep -q 'check-artifacts\.sh' "$S/clarify/SKILL.md"
assert_ok   "clarify gates on a settled spec instead"  grep -qi 'no open questions and no unconfirmed decisions' "$S/clarify/SKILL.md"
assert_ok   "clarify ends the turn after asking"       grep -qi 'end your turn' "$S/clarify/SKILL.md"
