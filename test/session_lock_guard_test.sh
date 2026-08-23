#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
GUARD="$SCRIPT_DIR/../scripts/session-lock-guard.sh"
LOCK="$SCRIPT_DIR/../scripts/session-lock.sh"

make_repo() {
  local dir; dir="$(mktemp -d)"
  dir="$(cd "$dir" && pwd -P)"
  git -C "$dir" init -q -b master
  mkdir -p "$dir/.kaba"
  cat > "$dir/.kaba/config.yml" <<'EOF'
test_dir:       spec/
test_command:   bundle exec rspec
feature_dir:    features/
test_writable:  [Gemfile, spec_support/]
linter_command: bundle exec rubocop
EOF
  printf '%s' "$dir"
}

payload_for_path() {
  jq -nc --arg tool "$1" --arg path "$2" \
    '{tool_name:$tool,tool_input:{file_path:$path}}'
}

payload_for_patch() {
  jq -nc --arg command "$1" \
    '{tool_name:"apply_patch",tool_input:{command:$command}}'
}

run_guard() {
  local payload="$1"
  (cd "$repo" && printf '%s' "$payload" | "$GUARD")
}

repo="$(make_repo)"

assert_ok "session-lock-guard.sh is executable" test -x "$GUARD"

# Claude path-declaring tools remain supported.
(cd "$repo" && "$LOCK" set implement >/dev/null)
assert_fail "Claude Write is blocked in locked test dir" 2 \
  run_guard "$(payload_for_path Write spec/models/x_spec.rb)"
assert_ok "Claude Edit is allowed outside locked test dir" \
  run_guard "$(payload_for_path Edit app/models/x.rb)"

# Codex sends the complete patch text instead of a direct path. Every touched
# source and destination path must be checked, not just the first file header.
(cd "$repo" && "$LOCK" set test >/dev/null)
assert_ok "Codex single-file test patch is allowed" \
  run_guard "$(payload_for_patch $'*** Begin Patch\n*** Add File: spec/models/x_spec.rb\n+test\n*** End Patch')"
assert_fail "Codex single-file implementation patch is blocked" 2 \
  run_guard "$(payload_for_patch $'*** Begin Patch\n*** Update File: app/models/x.rb\n@@\n-old\n+new\n*** End Patch')"
assert_fail "Codex multi-file patch checks every path" 2 \
  run_guard "$(payload_for_patch $'*** Begin Patch\n*** Add File: spec/models/ok_spec.rb\n+test\n*** Update File: app/models/bad.rb\n@@\n-old\n+new\n*** End Patch')"
assert_fail "Codex delete checks the deleted path" 2 \
  run_guard "$(payload_for_patch $'*** Begin Patch\n*** Delete File: app/models/dead.rb\n*** End Patch')"
assert_fail "Codex move checks the destination path" 2 \
  run_guard "$(payload_for_patch $'*** Begin Patch\n*** Update File: spec/models/x_spec.rb\n*** Move to: app/models/x.rb\n@@\n-old\n+new\n*** End Patch')"
assert_ok "Codex move within allowed paths is allowed" \
  run_guard "$(payload_for_patch $'*** Begin Patch\n*** Update File: spec/models/x_spec.rb\n*** Move to: spec/models/y_spec.rb\n@@\n-old\n+new\n*** End Patch')"

# A malformed patch cannot edit anything, so the cooperative hook stays out of
# the way and lets apply_patch itself report the syntax error.
assert_ok "malformed Codex patch fails open" \
  run_guard "$(payload_for_patch 'not a patch')"

plain="$(mktemp -d)"
plain="$(cd "$plain" && pwd -P)"
git -C "$plain" init -q -b master
assert_ok "non-kaba repo fails open for Codex patch" \
  sh -c "cd '$plain' && printf '%s' '$(payload_for_patch $'*** Begin Patch\n*** Add File: app/x.rb\n+x\n*** End Patch')' | '$GUARD'"

rm -rf "$repo" "$plain"
