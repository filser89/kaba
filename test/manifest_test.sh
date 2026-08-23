#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
M="$SCRIPT_DIR/../.claude-plugin"
C="$SCRIPT_DIR/../.codex-plugin"
ROOT="$SCRIPT_DIR/.."

# Claude Code and Codex load different repository instruction filenames. Both
# must exist and remain one contract rather than drifting into agent-specific rules.
assert_file_exists "Claude instructions exist" "$ROOT/CLAUDE.md"
assert_file_exists "Codex instructions exist" "$ROOT/AGENTS.md"
assert_ok "Claude and Codex instructions are identical" cmp -s "$ROOT/CLAUDE.md" "$ROOT/AGENTS.md"
assert_ok "agent rules define the changelog contract" grep -q '^## Changelog$' "$ROOT/CLAUDE.md"

# plugin.json and marketplace.json duplicate version and description. They drift
# silently, and a stale marketplace version makes `claude plugin update` a no-op —
# the update appears to succeed and ships nothing.
p_ver="$(jq -r '.version'                          "$M/plugin.json")"
m_ver="$(jq -r '.plugins[] | select(.name=="kaba") | .version'     "$M/marketplace.json")"
p_dsc="$(jq -r '.description'                      "$M/plugin.json")"
m_dsc="$(jq -r '.plugins[] | select(.name=="kaba") | .description' "$M/marketplace.json")"

assert_eq "manifests agree on version"     "$p_ver" "$m_ver"
assert_eq "manifests agree on description" "$p_dsc" "$m_dsc"

assert_stdout_match "version is semver" '^[0-9]+\.[0-9]+\.[0-9]+$' printf '%s' "$p_ver"

# `claude plugin validate` warns without an author, and --strict promotes that to an error.
assert_stdout_match "plugin declares an author" '.' jq -r '.author.name // empty' "$M/plugin.json"
assert_stdout_match "marketplace declares an owner" '.' jq -r '.owner.name // empty' "$M/marketplace.json"

# Codex uses a separate manifest schema but loads the same plugin root. Shared
# identity fields must not drift across hosts, and Codex-specific presentation
# metadata must remain present for ingestion.
c_ver="$(jq -r '.version'     "$C/plugin.json")"
c_dsc="$(jq -r '.description' "$C/plugin.json")"
assert_eq "Claude and Codex manifests agree on version"     "$p_ver" "$c_ver"
assert_eq "Claude and Codex manifests agree on description" "$p_dsc" "$c_dsc"
assert_eq "Codex manifest discovers root skills" "./skills/" \
  "$(jq -r '.skills' "$C/plugin.json")"
assert_stdout_match "Codex manifest has a display name" '.' \
  jq -r '.interface.displayName // empty' "$C/plugin.json"
assert_stdout_match "Codex manifest has a default prompt" '.' \
  jq -r '.interface.defaultPrompt[0] // empty' "$C/plugin.json"
assert_fail "Codex manifest does not declare unsupported hooks field" 1 \
  jq -e 'has("hooks")' "$C/plugin.json"
assert_ok "shared marketplace points Codex at the plugin root" \
  jq -e '.plugins[] | select(.name=="kaba" and .source=="./")' "$M/marketplace.json"

# Only plugin.json belongs inside .claude-plugin/; components live at the plugin root.
for d in skills scripts hooks templates; do
  assert_fail "$d/ is not inside .claude-plugin" 1 test -d "$M/$d"
  assert_ok   "$d/ is at the plugin root"          test -d "$SCRIPT_DIR/../$d"
done

# NOTICE names vendored files by path; a rename would leave the attribution dangling.
# The count is asserted because the failure mode here is silence: an extraction pattern
# that stops matching checks nothing and still reports green.
notice_paths=0
while IFS= read -r rel; do
  notice_paths=$((notice_paths + 1))
  assert_file_exists "NOTICE path $rel exists" "$SCRIPT_DIR/../$rel"
done < <(grep -oE '[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*\.md' "$SCRIPT_DIR/../NOTICE" | sort -u)
assert_eq "NOTICE still attributes 2 vendored files" "2" "$notice_paths"
