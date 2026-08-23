#!/usr/bin/env bash
# Claude Code and Codex PreToolUse hook: blocks edits that target paths locked by
# the active session mode (see session-lock.sh). Claude sends a direct file path;
# Codex sends the complete apply_patch text. Exit 2 blocks and feeds stderr to the
# agent.
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Not a kaba project — stay out of the way. The plugin's hook fires wherever the
# plugin is enabled, including repos that never ran /kaba:init.
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -f "$root/.kaba/config.yml" ] || exit 0

# No jq — fail open; the pre-commit hook still guards the commit boundary.
command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty')"

if [ "$tool_name" = "apply_patch" ]; then
  patch="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')"
  [ -n "$patch" ] || exit 0

  # apply_patch headers are the authoritative path declarations. An Update with
  # Move to touches both the old and new paths, so collect both. Preserve spaces
  # by building positional arguments one line at a time instead of using xargs.
  paths="$(printf '%s\n' "$patch" | sed -n -E \
    -e 's/^\*\*\* (Add|Update|Delete) File: (.*)$/\2/p' \
    -e 's/^\*\*\* Move to: (.*)$/\1/p')"
  [ -n "$paths" ] || exit 0

  set --
  while IFS= read -r file_path; do
    [ -n "$file_path" ] || continue
    set -- "$@" "$file_path"
  done <<EOF
$paths
EOF
  [ "$#" -gt 0 ] || exit 0

  if "$SCRIPT_DIR/session-lock.sh" check "$@"; then exit 0; else exit 2; fi
fi

file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
[ -n "$file_path" ] || exit 0

if "$SCRIPT_DIR/session-lock.sh" check "$file_path"; then exit 0; else exit 2; fi
