#!/usr/bin/env bash
# Claude Code PreToolUse hook: blocks Edit/Write/NotebookEdit calls that target
# paths locked by the active session mode (see session-lock.sh). Reads the hook
# payload JSON on stdin and delegates. Exit 2 blocks and feeds stderr to the agent.
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Not a kaba project — stay out of the way. The plugin's hook fires wherever the
# plugin is enabled, including repos that never ran /kaba:init.
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -f "$root/.kaba/config.yml" ] || exit 0

# No jq — fail open; the pre-commit hook still guards the commit boundary.
command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
[ -z "$file_path" ] && exit 0

if "$SCRIPT_DIR/session-lock.sh" check "$file_path"; then exit 0; else exit 2; fi
