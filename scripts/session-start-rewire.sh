#!/usr/bin/env bash
# SessionStart hook: re-point kaba.scriptdir at the plugin copy that is actually running.
#
# init-project.sh pins kaba.scriptdir to an absolute path, and for a marketplace install
# that path carries a version segment (…/kaba/0.1.0/scripts). Every version bump strands
# it: the consumer loads new command text from the new plugin directory while the pinned
# path still points at the old one. A command that calls a script only present in the new
# version gets "No such file or directory" — which reads to the model as no answer, and a
# gate with no answer is a gate that does not fire.
#
# ${CLAUDE_PLUGIN_ROOT} always resolves to the running copy, so comparing against it and
# rewriting on drift fixes the class permanently rather than one bump at a time.
#
# Fails open in anything that is not a kaba project. kaba installs at user scope by
# default, so this runs in every repo the user opens — same rule as session-lock-guard.sh.
set -uo pipefail

# No plugin root (not running as a plugin hook) or no project dir — nothing to do.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || exit 0
[ -n "${CLAUDE_PROJECT_DIR:-}" ] || exit 0

root="$(git -C "$CLAUDE_PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$root" ] || exit 0
[ -f "$root/.kaba/config.yml" ] || exit 0

want="$CLAUDE_PLUGIN_ROOT/scripts"
# Never point the consumer at a directory that isn't there — a wrong pin is worse than
# a stale one, because the stale one at least used to work.
[ -d "$want" ] || exit 0

have="$(git -C "$root" config kaba.scriptdir 2>/dev/null || true)"
[ "$have" = "$want" ] && exit 0

git -C "$root" config kaba.scriptdir "$want" 2>/dev/null || exit 0
echo "kaba: re-pointed kaba.scriptdir at $want"
