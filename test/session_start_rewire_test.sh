#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
REWIRE="$SCRIPT_DIR/../scripts/session-start-rewire.sh"

# A fake plugin root: the thing whose path changes on every version bump.
make_plugin() {
  local ver="$1" base; base="$(mktemp -d)"
  base="$(cd "$base" && pwd -P)"
  mkdir -p "$base/$ver/scripts"
  printf '%s' "$base/$ver"
}

make_repo() {
  local kaba="$1" dir; dir="$(mktemp -d)"
  dir="$(cd "$dir" && pwd -P)"
  git -C "$dir" init -q -b master
  if [ "$kaba" = "kaba" ]; then
    mkdir -p "$dir/.kaba"
    printf 'test_dir: spec/\n' > "$dir/.kaba/config.yml"
  fi
  printf '%s' "$dir"
}

run() { CLAUDE_PLUGIN_ROOT="$1" CLAUDE_PROJECT_DIR="$2" bash "$REWIRE"; }
pin() { git -C "$1" config kaba.scriptdir 2>/dev/null || true; }

assert_ok "session-start-rewire.sh is executable" test -x "$REWIRE"
assert_ok "hooks.json declares the SessionStart hook" \
  grep -q "session-start-rewire\.sh" "$SCRIPT_DIR/../hooks/hooks.json"
assert_ok "hooks.json still declares the PreToolUse guard" \
  grep -q "session-lock-guard\.sh" "$SCRIPT_DIR/../hooks/hooks.json"

# --- the stranded-pin case this exists for ---------------------------------------
old="$(make_plugin 0.1.0)"
new="$(make_plugin 0.2.0)"
r="$(make_repo kaba)"
git -C "$r" config kaba.scriptdir "$old/scripts"

assert_ok "rewire exits 0" run "$new" "$r"
assert_eq "stale pin is re-pointed at the running version" "$new/scripts" "$(pin "$r")"

git -C "$r" config kaba.scriptdir "$old/scripts"   # re-stale it; the run above fixed it
assert_stdout_match "rewire says what it did" 're-pointed kaba.scriptdir' run "$new" "$r"

# --- idempotent: an already-correct pin is left alone and stays quiet -------------
out="$(run "$new" "$r")"
assert_eq "second run is a no-op" "" "$out"
assert_eq "pin unchanged after no-op" "$new/scripts" "$(pin "$r")"

# --- fail open: not a kaba project -----------------------------------------------
# This matters because the plugin installs at user scope, so the hook runs in every
# repo the user opens.
plain="$(make_repo plain)"
assert_ok "non-kaba repo exits 0" run "$new" "$plain"
assert_eq "non-kaba repo is never written to" "" "$(pin "$plain")"
assert_eq "non-kaba repo produces no output" "" "$(run "$new" "$plain")"

# --- fail open: not a git repo at all --------------------------------------------
bare="$(mktemp -d)"
assert_ok "non-git dir exits 0" run "$new" "$bare"

# --- fail open: missing env ------------------------------------------------------
assert_ok "no CLAUDE_PLUGIN_ROOT exits 0"  bash -c "CLAUDE_PROJECT_DIR='$r' bash '$REWIRE'"
assert_ok "no CLAUDE_PROJECT_DIR exits 0"  bash -c "CLAUDE_PLUGIN_ROOT='$new' bash '$REWIRE'"

# --- never pin at a scripts dir that does not exist -------------------------------
# A wrong pin is worse than a stale one: the stale one at least used to work.
ghost="$(mktemp -d)/nonexistent"
git -C "$r" config kaba.scriptdir "$old/scripts"
assert_ok "missing scripts dir exits 0" run "$ghost" "$r"
assert_eq "missing scripts dir leaves the pin alone" "$old/scripts" "$(pin "$r")"

rm -rf "$old" "$new" "$r" "$plain" "$bare"
