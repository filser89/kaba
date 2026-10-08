#!/usr/bin/env bash
# Public snapshot gates protect fixture aliases without inspecting unrelated links.
set -uo pipefail
SCRIPT_DIR="$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
PI_SCRIPTS="$(cd "$SCRIPT_DIR/../scripts" && pwd)"
PI_ROOT="$(mktemp -d)"
export GOCACHE="${GOCACHE:-${TMPDIR:-/tmp}/kaba-go-build}"
git -C "$PI_ROOT" init -q
mkdir -p "$PI_ROOT/.kaba" "$PI_ROOT/features/one" "$PI_ROOT/testdata/actual" "$PI_ROOT/shared-data" "$PI_ROOT/.venv/bin"
cat > "$PI_ROOT/.kaba/config.yml" <<'CFG'
test_runner: go
test_command: go test ./...
linter_command: "true"
feature_dir: features/
test_write_allow: ["**/*_test.go", "testdata/**", "shared-data/**", "features/**"]
test_write_exclude: []
implement_write_allow: ["**"]
implement_write_exclude: ["**/*_test.go", "testdata/**"]
CFG
printf 'module inventory.test\n\ngo 1.23\n' > "$PI_ROOT/go.mod"
printf 'package inventory\nimport "testing"\nfunc TestOne(t *testing.T) {}\n' > "$PI_ROOT/one_test.go"
printf fixture > "$PI_ROOT/testdata/actual/input"
ln -s actual "$PI_ROOT/testdata/link"
pi_snapshot() {
  (cd "$PI_ROOT" && export FEATURE_DIR="$PI_ROOT/features/one"
   bash "$PI_SCRIPTS/snapshot-tests.sh" "$@" || exit
   if [[ "${1:-}:${2:-}" == capture:post-test ]]; then bash "$PI_SCRIPTS/snapshot-tests.sh" compare post-test; fi)
}
assert_ok 'protected snapshot fixture captures baseline' pi_snapshot capture baseline
printf '{"version":3,"entries":[]}\n' > "$PI_ROOT/features/one/test-plan.json"
assert_ok 'protected snapshot fixture validates plan' pi_snapshot validate-plan
assert_ok 'test-owned directory symlink supports post-test capture' pi_snapshot capture post-test
assert_ok 'unchanged directory symlink supports implementation capture' pi_snapshot capture post-impl
assert_ok 'unchanged directory symlink passes locked comparison' pi_snapshot compare post-impl
printf changed > "$PI_ROOT/testdata/actual/input"
assert_ok 'directory symlink target mutation remains capturable' pi_snapshot capture post-impl
assert_fail 'directory symlink target mutation fails locked comparison' 1 pi_snapshot compare post-impl
printf fixture > "$PI_ROOT/testdata/actual/input"
# The resolved directory is shared, but the test-owned alias must protect its contents.
printf shared > "$PI_ROOT/shared-data/input"
ln -s ../shared-data "$PI_ROOT/testdata/shared"
assert_stdout_match 'subtree permission covers directory symlink target itself' '^test$' bash -c 'cd "$1" && bash "$2/path-permissions.sh" classify testdata/shared' _ "$PI_ROOT" "$PI_SCRIPTS"
assert_ok 'test-owned alias into shared fixture directory is captured' pi_snapshot capture post-test
printf modified > "$PI_ROOT/shared-data/input"
assert_ok 'shared target modification is captured through protected alias' pi_snapshot capture post-impl
assert_fail 'shared target modification fails protected alias comparison' 1 pi_snapshot compare post-impl
printf shared > "$PI_ROOT/shared-data/input"
assert_ok 'restored shared fixture permits capture' pi_snapshot capture post-test
rm "$PI_ROOT/testdata/shared"
ln -s actual "$PI_ROOT/testdata/shared"
assert_ok 'fixture symlink retargeting is captured' pi_snapshot capture post-impl
assert_fail 'fixture symlink retargeting fails locked comparison' 1 pi_snapshot compare post-impl
# Ignored non-test links are not immutable test inputs and must not block capture.
ln -s /usr/bin/true "$PI_ROOT/.venv/bin/python"
ln -s missing "$PI_ROOT/.venv/bin/dangling"
printf '.venv/\n' > "$PI_ROOT/.gitignore"
assert_ok 'ignored external and dangling non-test links do not block capture' pi_snapshot capture post-test
assert_ok 'ignored non-test links do not block implementation capture' pi_snapshot capture post-impl
assert_ok 'ignored non-test links do not affect locked comparison' pi_snapshot compare post-impl
# Directory ownership need not equal the ownership of its descendants.
sed -e 's/"testdata\/\*\*"/"testdata\/**", "alias\/fixtures\/**"/g' "$PI_ROOT/.kaba/config.yml" > "$PI_ROOT/.kaba/new.yml"
mv "$PI_ROOT/.kaba/new.yml" "$PI_ROOT/.kaba/config.yml"
mkdir -p "$PI_ROOT/shared-data/fixtures"
printf nested > "$PI_ROOT/shared-data/fixtures/input"
ln -s shared-data "$PI_ROOT/alias"
assert_ok 'neutral directory alias with test-owned descendants is captured' pi_snapshot capture post-test
printf changed > "$PI_ROOT/shared-data/fixtures/input"
assert_ok 'neutral alias descendant mutation is captured' pi_snapshot capture post-impl
assert_fail 'neutral alias cannot hide changed test-owned descendants' 1 pi_snapshot compare post-impl
mkdir -p "$PI_ROOT/testdata/git-fixture/.git"
printf branch > "$PI_ROOT/testdata/git-fixture/.git/HEAD"
assert_ok 'Git repository fixtures are captured' pi_snapshot capture post-test
printf other > "$PI_ROOT/testdata/git-fixture/.git/HEAD"
assert_ok 'Git repository fixture mutation is captured' pi_snapshot capture post-impl
assert_fail 'nested fixture Git metadata is protected' 1 pi_snapshot compare post-impl
ln -s /usr/bin/true "$PI_ROOT/testdata/outside"
assert_fail 'test-owned outside symlink still blocks capture' 1 pi_snapshot capture post-impl
rm "$PI_ROOT/testdata/outside"
ln -s nowhere "$PI_ROOT/testdata/dangling"
assert_fail 'test-owned dangling symlink still blocks capture' 1 pi_snapshot capture post-impl
rm "$PI_ROOT/testdata/dangling"
rm -rf "$PI_ROOT"
