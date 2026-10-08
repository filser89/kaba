#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
LOCK="$SCRIPT_DIR/../scripts/session-lock.sh"
HOOK="$SCRIPT_DIR/../scripts/hooks/pre-commit"
CHANGED="$SCRIPT_DIR/../scripts/changed-paths.sh"
repo="$(mktemp -d)"
git -C "$repo" init -q
mkdir -p "$repo/.kaba" "$repo/internal/pay/testdata"
cp "$SCRIPT_DIR/fixtures/go-config.yml" "$repo/.kaba/config.yml"
printf '.kaba/session-lock\n' > "$repo/.gitignore"
printf 'package pay\n' > "$repo/internal/pay/pay.go"
printf 'package pay\n' > "$repo/internal/pay/pay_test.go"
printf '{}\n' > "$repo/internal/pay/testdata/input data.json"
ln -s pay_test.go "$repo/internal/pay/alias.go"
ln -s ../pay_test.go "$repo/internal/pay/testdata/alias_test.go"
ln -s bridge.go "$repo/internal/pay/chain.go"
ln -s pay_test.go "$repo/internal/pay/bridge.go"
ln -s bridge_test.go "$repo/internal/pay/testdata/chain_test.go"
ln -s ../pay_test.go "$repo/internal/pay/testdata/bridge_test.go"
printf 'package pay\n' > "$repo/internal/pay/testdata/pay.go"
ln -s testdata "$repo/internal/pay/redirect"
ln -s redirect/pay.go "$repo/internal/pay/ancestor.go"
git -C "$repo" add .
git -C "$repo" -c user.name=Kaba -c user.email=kaba@example.invalid commit -qm fixture
git -C "$repo" config kaba.scriptdir "$(cd "$SCRIPT_DIR/../scripts" && pwd)"
lock() { (cd "$repo" && "$LOCK" "$@"); }
hook() { (cd "$repo" && "$HOOK"); }
changed() { (cd "$repo" && bash "$CHANGED" "$1" | tr '\000' '\n'); }
changed_nested() { (cd "$repo/internal/pay" && bash "$CHANGED" "$1" | tr '\000' '\n'); }
hook_nested() { (cd "$repo/internal/pay" && "$HOOK"); }
reset_fixture() { git -C "$repo" reset --hard -q HEAD; git -C "$repo" clean -fdq; }
lock set implement >/dev/null
printf 'package pay\n// staged test\n' > "$repo/internal/pay/pay_test.go"
git -C "$repo" add internal/pay/pay_test.go
assert_fail "commit blocks staged colocated test" 1 hook
assert_fail "dirty gate checks staged test independently" 1 lock check-dirty implement
assert_ok "dirty gate checks requested test mode" lock check-dirty test
assert_stdout_match "dirty inventory retains staged path" '^internal/pay/pay_test.go$' changed dirty
assert_stdout_match "nested inventory retains root-relative staged path" '^internal/pay/pay_test.go$' changed_nested dirty
reset_fixture
printf '// unstaged\n' >> "$repo/internal/pay/pay_test.go"
assert_fail "dirty gate checks unstaged test" 1 lock check-dirty implement
assert_ok "commit gate only checks staged paths" hook
assert_stdout_match "dirty inventory retains unstaged path" '^internal/pay/pay_test.go$' changed dirty
reset_fixture
printf '{}\n' > "$repo/internal/pay/testdata/new input.json"
assert_fail "dirty gate checks untracked fixture with spaces" 1 lock check-dirty implement
assert_stdout_match "dirty inventory preserves untracked spaces" '^internal/pay/testdata/new input.json$' changed dirty
assert_stdout_match "nested inventory retains root-relative untracked path" '^internal/pay/testdata/new input.json$' changed_nested dirty
git -C "$repo" add 'internal/pay/testdata/new input.json'
assert_fail "commit gate checks staged fixture addition" 1 hook
reset_fixture
git -C "$repo" rm -q internal/pay/pay_test.go
assert_fail "commit blocks absent deleted test" 1 hook
assert_fail "dirty gate blocks absent deleted test" 1 lock check-dirty implement
assert_stdout_match "dirty inventory retains absent deleted path" '^internal/pay/pay_test.go$' changed dirty
reset_fixture
git -C "$repo" mv internal/pay/pay_test.go internal/pay/new.go
assert_fail "commit move checks old test path" 1 hook
assert_stdout_match "inventory contains old move endpoint" '^internal/pay/pay_test.go$' changed staged
assert_stdout_match "inventory contains new move endpoint" '^internal/pay/new.go$' changed staged
reset_fixture
git -C "$repo" mv internal/pay/pay.go internal/pay/new_test.go
assert_fail "commit move checks new test path" 1 hook
lock set test >/dev/null
assert_fail "test commit move checks old production path" 1 hook
reset_fixture
printf '// implementation\n' >> "$repo/internal/pay/pay.go"
git -C "$repo" add internal/pay/pay.go
assert_fail "test commit blocks staged production" 1 hook
assert_fail "test dirty gate blocks staged production" 1 lock check-dirty test
reset_fixture
git -C "$repo" rm -q internal/pay/alias.go
lock set implement >/dev/null
assert_fail "commit retains deleted symlink target ownership" 1 hook
assert_fail "dirty gate retains deleted symlink target ownership" 1 lock check-dirty implement
reset_fixture
rm "$repo/internal/pay/alias.go"
assert_fail "dirty gate retains unstaged deleted symlink target" 1 lock check-dirty implement
reset_fixture
git -C "$repo" rm -q internal/pay/chain.go
rm "$repo/internal/pay/bridge.go"
printf 'package pay\n' > "$repo/internal/pay/bridge.go"
assert_fail "staged deletion follows HEAD chain despite unstaged regular replacement" 1 lock check-staged implement
assert_fail "commit follows HEAD chain despite unstaged regular replacement" 1 hook
reset_fixture
# Index links must also use index targets rather than unstaged replacements.
ln -s bridge.go "$repo/internal/pay/new-chain.go"
git -C "$repo" add internal/pay/new-chain.go
rm "$repo/internal/pay/new-chain.go" "$repo/internal/pay/bridge.go"
printf 'package pay\n' > "$repo/internal/pay/new-chain.go"
printf 'package pay\n' > "$repo/internal/pay/bridge.go"
assert_fail "staged addition follows index chain despite unstaged regular replacements" 1 lock check-staged implement
reset_fixture
git -C "$repo" rm -q internal/pay/ancestor.go
rm "$repo/internal/pay/redirect"
mkdir "$repo/internal/pay/redirect"
printf 'package pay\n' > "$repo/internal/pay/redirect/pay.go"
assert_fail "staged deletion follows HEAD ancestor link despite unstaged directory replacement" 1 lock check-staged implement
reset_fixture
git -C "$repo" rm -q internal/pay/testdata/alias_test.go
lock set test >/dev/null
assert_ok "commit allows deleted same-owner symlink" hook
assert_ok "dirty gate allows deleted same-owner symlink" lock check-dirty test
reset_fixture
rm "$repo/internal/pay/testdata/alias_test.go"
assert_ok "dirty gate allows unstaged deleted same-owner symlink" lock check-dirty test
reset_fixture
git -C "$repo" rm -q internal/pay/testdata/alias_test.go internal/pay/pay_test.go
assert_ok "commit allows same-owner symlink and target deletion" hook
assert_ok "dirty gate allows same-owner symlink and target deletion" lock check-dirty test
reset_fixture
git -C "$repo" rm -q internal/pay/testdata/chain_test.go internal/pay/testdata/bridge_test.go internal/pay/pay_test.go
assert_ok "commit allows same-owner historical chain joint deletion" hook
assert_ok "dirty gate allows same-owner historical chain joint deletion" lock check-dirty test
reset_fixture
git -C "$repo" rm -q internal/pay/alias.go
lock set implement >/dev/null
assert_fail "nested commit retains historical symlink ownership" 1 hook_nested
reset_fixture
lock set implement >/dev/null
printf x > "$repo/internal/pay/"$'trailing\n.go'
git -C "$repo" add .
assert_fail "commit rejects control characters losslessly" 1 hook
assert_fail "dirty gate rejects control characters losslessly" 1 lock check-dirty implement
assert_stderr_match "control rejection identifies unsupported path" 'control character' lock check-dirty implement
lock clear >/dev/null
assert_ok "commit preserves off mode" hook
assert_ok "dirty gate explicit off preserves off mode" lock check-dirty off
assert_fail "dirty gate rejects invalid requested mode" 1 lock check-dirty banana
reset_fixture
assert_ok "clean dirty gate succeeds" lock check-dirty implement
rm -rf "$repo"
