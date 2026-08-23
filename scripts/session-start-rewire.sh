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
# Claude exposes the running copy and project as environment variables. Codex expands
# the same plugin-root placeholder when loading the hook and provides the project cwd in
# the SessionStart payload; the installed script can also derive its root from its path.
#
# Fails open in anything that is not a kaba project. kaba installs at user scope by
# default, so this runs in every repo the user opens — same rule as session-lock-guard.sh.
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

payload="$(cat)"
plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
project_dir="${CLAUDE_PROJECT_DIR:-}"

[ -n "$plugin_root" ] || plugin_root="$(dirname "$SCRIPT_DIR")"
if [ -z "$project_dir" ] && [ -n "$payload" ] && command -v jq >/dev/null 2>&1; then
  project_dir="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
fi

# No plugin root (not running as a plugin hook) or no project dir — nothing to do.
[ -n "$plugin_root" ] || exit 0
[ -n "$project_dir" ] || exit 0

root="$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$root" ] || exit 0
[ -f "$root/.kaba/config.yml" ] || exit 0

want="$plugin_root/scripts"
# Never point the consumer at a directory that isn't there — a wrong pin is worse than
# a stale one, because the stale one at least used to work.
[ -d "$want" ] || exit 0

have="$(git -C "$root" config kaba.scriptdir 2>/dev/null || true)"
[ "$have" = "$want" ] && exit 0

git -C "$root" config kaba.scriptdir "$want" 2>/dev/null || exit 0
echo "kaba: re-pointed kaba.scriptdir at $want"
