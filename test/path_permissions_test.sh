#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
PERMISSIONS="$SCRIPT_DIR/../scripts/path-permissions.sh"
repo="$(mktemp -d)"
git -C "$repo" init -q
mkdir -p "$repo/.kaba" "$repo/internal/pay" "$repo/internal/testutil" "$repo/spec"
cp "$SCRIPT_DIR/fixtures/go-config.yml" "$repo/.kaba/config.yml"
classify() { (cd "$repo" && bash "$PERMISSIONS" classify "$1"); }
assert_stdout_match "root test is test-owned" '^test$' classify pay_test.go
assert_stdout_match "colocated test is test-owned" '^test$' classify internal/pay/pay_test.go
assert_stdout_match "production is implementation-owned" '^implement$' classify internal/pay/pay.go
assert_stdout_match "manifest is shared" '^shared$' classify go.mod
assert_stdout_match "workflow artifacts are shared" '^shared$' classify features/a/spec.md
assert_stdout_match "future fixture is test-owned" '^test$' classify new/package/testdata/input.json
assert_stdout_match "root fixture is test-owned" '^test$' classify testdata/input.json
assert_stdout_match "shared test helper is test-owned" '^test$' classify internal/testutil/helper.go
assert_stdout_match "leading dots and separators normalized" '^test$' classify ././internal//pay/pay_test.go
assert_stdout_match "absolute future test path works" '^test$' classify "$repo/new/pay_test.go"
assert_fail "traversal rejected" 1 classify internal/../pay_test.go
assert_fail "outside path rejected" 1 classify /tmp/kaba-outside_test.go
assert_fail "empty path rejected" 1 classify ''
printf 'pay_test.go\n' > "$repo/.gitignore"
assert_stdout_match "gitignore does not change permissions" '^test$' classify pay_test.go
ln -s pay_test.go "$repo/internal/pay/alias.go"
touch "$repo/internal/pay/pay_test.go"
assert_stdout_match "symlink intersects implementation and test" '^none$' classify internal/pay/alias.go
ln -s testutil "$repo/internal/helpers"
assert_stdout_match "future file under symlink intersects permissions" '^none$' classify internal/helpers/new.go
ln -s nowhere "$repo/dangling_test.go"
assert_fail "dangling symlink rejected" 1 classify dangling_test.go
ln -s loop_test.go "$repo/loop_test.go"
assert_fail "cyclic symlink rejected" 1 classify loop_test.go
ln -s /tmp "$repo/internal/pay/outside"
assert_fail "outside symlink rejected" 1 classify internal/pay/outside/new_test.go
# Exclusions win even with broad allows; independent allows may reject both sessions.
cat > "$repo/.kaba/config.yml" <<'CFG'
test_runner: go
test_command: go test ./...
linter_command: make verify
feature_dir: features/
test_write_allow: ['**', 'excluded/**']
test_write_exclude: ['excluded/']
implement_write_allow: ['app/**']
implement_write_exclude: ['app/private/**']
CFG
assert_stdout_match "exclusion wins over later allow" '^none$' classify excluded/a.go
assert_stdout_match "implementation exclusion independent" '^test$' classify app/private/a.go
assert_stdout_match "independent overlapping allows shared" '^shared$' classify app/a.go
# Legacy entries are literal exact paths or literal subtrees, never patterns.
cat > "$repo/.kaba/config.yml" <<'CFG'
test_dir: spec/
test_command: bundle exec rspec
linter_command: bundle exec rubocop
feature_dir: features/
test_writable: ['config/[test].rb', 'literal*', 'support/']
CFG
assert_stdout_match "legacy tests retain ownership" '^test$' classify spec/a_spec.rb
assert_stdout_match "legacy workflow shared" '^shared$' classify features/a/spec.md
assert_stdout_match "legacy bracket carve-out is literal" '^shared$' classify 'config/[test].rb'
assert_stdout_match "legacy bracket does not glob" '^implement$' classify config/t.rb
assert_stdout_match "legacy star carve-out is literal" '^shared$' classify 'literal*'
assert_stdout_match "legacy exact carve-out excludes children" '^implement$' classify 'literal*/child'
assert_stdout_match "legacy subtree carve-out" '^shared$' classify support/a/helper.rb
assert_stdout_match "legacy subtree boundary anchored" '^implement$' classify supports/a.rb
rm -rf "$repo"
# Wildcards respect segment boundaries and escape regular-expression literals.
repo="$(mktemp -d)"
git -C "$repo" init -q
mkdir -p "$repo/.kaba"
cat > "$repo/.kaba/config.yml" <<'CFG'
test_runner: go
test_command: go test ./...
linter_command: make verify
feature_dir: features/
test_write_allow: ['internal/*.go', 'root/', '**/any/', 'file.with+(x)', 'path with spaces/**']
test_write_exclude: []
implement_write_allow: ['app/**']
implement_write_exclude: []
CFG
assert_stdout_match "single star matches segment" '^test$' classify internal/file.go
assert_stdout_match "single star cannot cross directory" '^none$' classify internal/deep/file.go
assert_stdout_match "trailing slash includes subtree" '^test$' classify root/nested/file
assert_stdout_match "trailing slash anchored at root" '^none$' classify nested/root/file
assert_stdout_match "globstar matches root directory" '^test$' classify any/file
assert_stdout_match "globstar matches nested directory" '^test$' classify nested/any/file
assert_stdout_match "regex characters matched literally" '^test$' classify 'file.with+(x)'
assert_stdout_match "regex characters do not broaden pattern" '^none$' classify fileXwithx
assert_stdout_match "spaces preserved" '^test$' classify 'path with spaces/nested file'
assert_fail "internal dot segment rejected" 1 classify internal/./file.go
assert_stdout_match "missing deleted leaf retains classification" '^test$' classify internal/deleted.go
rm -rf "$repo"
