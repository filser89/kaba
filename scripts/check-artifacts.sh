#!/usr/bin/env bash
# Reports whether a pipeline step has already completed for the current feature, so
# the command can stop and ask before it spends tokens regenerating something.
#
# Takes a COMMAND NAME, not a list of filenames. The command → artifact mapping lives
# here, in one testable case statement, rather than as prose in six command bodies:
# a mistyped filename there would report PRIOR_RUN=no — indistinguishable from a clean
# feature directory — and silently reproduce the very overwrite this gate prevents.
#
# Exit status is health, never the answer. 0 means "answered" (read PRIOR_RUN);
# non-zero means the question could not be asked at all, and the caller must stop.
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/config.sh"

COMMANDS="specify acceptance-criteria plan-tests plan-code implement-tests implement-code"

cmd="${1:-}"
[ -n "$cmd" ] || kaba_die "usage: check-artifacts.sh <command>  (one of: $COMMANDS)"
[ "$#" -eq 1 ] || kaba_die "check-artifacts.sh takes exactly one argument, got $#"
case "$cmd" in
  *[[:space:]]*) kaba_die "command name must not contain whitespace (got '$cmd')" ;;
esac

# The mapping. Every entry is a completion marker — a file that exists only after a
# run finished — never in-progress state. That is what keeps the documented resume
# paths alive: implement-tests keys on post-test.json rather than baseline.json,
# because baseline.json is present mid-session by design (snapshot-tests.sh:129-139).
case "$cmd" in
  specify)             artifacts="spec.md" ;;
  acceptance-criteria) artifacts="acceptance-criteria.md" ;;
  plan-tests)          artifacts="test-plan.md test-plan.json" ;;
  plan-code)           artifacts="code-plan.md" ;;
  implement-tests)     artifacts="snapshots/post-test.json" ;;
  implement-code)      artifacts="snapshots/post-impl.json" ;;
  *) kaba_die "unknown command '$cmd' — expected one of: $COMMANDS" ;;
esac

reason=""

# FEATURE_DIR may be pre-set for smoke-testing only — same escape hatch as
# snapshot-tests.sh:69. Normal runs resolve it from the branch.
if [ -z "${FEATURE_DIR:-}" ]; then
  rc=0
  out="$("$SCRIPT_DIR/resolve-feature.sh" 2>/dev/null)" || rc=$?
  case "$rc" in
    0)
      while IFS= read -r line; do
        case "$line" in FEATURE_DIR=*) FEATURE_DIR="${line#FEATURE_DIR=}" ;; esac
      done <<EOF
$out
EOF
      ;;
    3)
      # Benign: no feature branch yet. Only /kaba:specify treats this as normal.
      reason="no-feature-branch"
      ;;
    *)
      # A real fault (no matching directory, or an ambiguous match). Re-run to let
      # resolve-feature.sh's own stderr reach the caller, then die — the caller's
      # fail-closed rule turns a non-zero exit into a stop, which is what an
      # unresolvable feature must produce. It must never read as a fresh start.
      "$SCRIPT_DIR/resolve-feature.sh" >/dev/null || true
      kaba_die "could not resolve the feature (resolve-feature.sh exit $rc)"
      ;;
  esac
fi

existing=""
missing=""
empty=""
if [ -n "${FEATURE_DIR:-}" ]; then
  for a in $artifacts; do
    p="$FEATURE_DIR/$a"
    if [ -e "$p" ]; then
      existing="${existing:+$existing }$a"
      # A 0-byte artifact still counts as existing: a truncated file from a crashed
      # run is worthless, but a re-run destroys it just as irrecoverably. Report it
      # and let the human decide rather than applying a size heuristic here.
      [ -s "$p" ] || empty="${empty:+$empty }$a"
    else
      missing="${missing:+$missing }$a"
    fi
  done
fi

if [ -z "${FEATURE_DIR:-}" ]; then
  prior="unknown"
elif [ "$cmd" = "specify" ]; then
  # specify does not overwrite: new-feature.sh allocates the NEXT number and branches
  # off HEAD. Its hazard is a stray feature created off the current one, so the gate
  # is "did a feature resolve at all", not "does spec.md exist". Gating on the file
  # would sail past the ordinary interrupted case — branch and directory created,
  # spec.md not yet written.
  prior="yes"
elif [ -n "$existing" ]; then
  prior="yes"
else
  prior="no"
fi

printf 'PRIOR_RUN=%s\n'   "$prior"
printf 'REASON=%s\n'      "$reason"
printf 'FEATURE_DIR=%s\n' "${FEATURE_DIR:-}"
printf 'EXISTING=%s\n'    "$existing"
printf 'MISSING=%s\n'     "$missing"
printf 'EMPTY=%s\n'       "$empty"
