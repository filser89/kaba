#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
GS_SNAP="$SCRIPT_DIR/../scripts/snapshot-tests.sh"
GS_ROOT="$(mktemp -d)"
git -C "$GS_ROOT" init -q
mkdir -p "$GS_ROOT/.kaba" "$GS_ROOT/features/one/snapshots" "$GS_ROOT/testdata"
cat > "$GS_ROOT/.kaba/config.yml" <<'CFG'
test_runner: go
test_command: go test ./...
linter_command: "true"
feature_dir: features/
test_write_allow: ["**/*_test.go", "testdata/**", "features/**"]
test_write_exclude: []
implement_write_allow: ["**"]
implement_write_exclude: ["**/*_test.go", "testdata/**"]
CFG
printf 'module protected.test\n\ngo 1.23\n' > "$GS_ROOT/go.mod"
printf 'package protected\nimport "testing"\nfunc TestOne(t *testing.T) {}\n' > "$GS_ROOT/one_test.go"
printf fixture > "$GS_ROOT/testdata/ignored"
printf 'testdata/ignored\n' > "$GS_ROOT/.gitignore"
git -C "$GS_ROOT" add .
git -C "$GS_ROOT" -c user.name=Test -c user.email=test@example.test commit -qm fixture
gs_run() {
  (cd "$GS_ROOT" && export GOCACHE="${TMPDIR:-/tmp}/kaba-go-build" FEATURE_DIR="$GS_ROOT/features/one"
   bash "$GS_SNAP" "$@" || exit
   if [[ "${1:-}:${2:-}" == capture:post-test ]]; then bash "$GS_SNAP" compare post-test; fi)
}
assert_ok 'protected fixture captures baseline before test writing' gs_run capture baseline
printf '{"version":3,"entries":[]}\n' > "$GS_ROOT/features/one/test-plan.json"
assert_ok 'protected fixture validates its empty plan' gs_run validate-plan
assert_ok 'capture records protected ignored fixture' gs_run capture post-test
assert_eq 'ignored fixture occurs in protected inventory' 1 "$(jq '[.protected_files[]? | select(.path=="testdata/ignored")]|length' "$GS_ROOT/features/one/snapshots/post-test.json")"
assert_eq 'shared feature artifacts excluded from protected inventory' 0 "$(jq '[.protected_files[]? | select(.path|startswith("features/"))]|length' "$GS_ROOT/features/one/snapshots/post-test.json")"
assert_ok 'unchanged implementation protected files pass' gs_run capture post-impl
assert_ok 'protected inventory same passes comparison' gs_run compare post-impl
printf changed > "$GS_ROOT/testdata/ignored"
assert_ok 'fixture mutation capture completes' gs_run capture post-impl
assert_fail 'fixture content mutation fails postimpl comparison' 1 gs_run compare post-impl
mv "$GS_ROOT/testdata/ignored" "$GS_ROOT/testdata/renamed"
assert_ok 'fixture rename capture completes' gs_run capture post-impl
assert_fail 'fixture rename fails postimpl comparison' 1 gs_run compare post-impl
rm "$GS_ROOT/testdata/renamed"
printf helper > "$GS_ROOT/testdata/helper"
assert_ok 'fixture addition capture completes' gs_run capture post-impl
assert_fail 'fixture addition fails postimpl comparison' 1 gs_run compare post-impl
rm "$GS_ROOT/testdata/helper"
assert_ok 'fixture deletion capture completes' gs_run capture post-impl
assert_fail 'fixture deletion fails postimpl comparison' 1 gs_run compare post-impl
cp "$GS_ROOT/features/one/snapshots/post-test.json" "$GS_ROOT/features/one/snapshots/baseline.json"
GS_HASH="$(git hash-object "$GS_ROOT/features/one/snapshots/baseline.json")"
git -C "$GS_ROOT" rm -q one_test.go
assert_ok 'resume detects removed test-owned old path' gs_run capture baseline
assert_eq 'resume preserves baseline bytes' "$GS_HASH" "$(git hash-object "$GS_ROOT/features/one/snapshots/baseline.json")"
git -C "$GS_ROOT" checkout HEAD -- one_test.go
printf fixture > "$GS_ROOT/testdata/ignored"
cp "$GS_ROOT/features/one/snapshots/post-test.json" "$GS_ROOT/features/one/snapshots/baseline.json"
GS_HASH="$(git hash-object "$GS_ROOT/features/one/snapshots/baseline.json")"
printf changed > "$GS_ROOT/testdata/ignored"
assert_ok 'resume detects ignored test fixture content change' gs_run capture baseline
assert_eq 'ignored fixture resume preserves baseline bytes' "$GS_HASH" "$(git hash-object "$GS_ROOT/features/one/snapshots/baseline.json")"
jq '.examples[0].status="failed"' "$GS_ROOT/features/one/snapshots/post-test.json" > "$GS_ROOT/before.json"
jq '.examples[0].status="passed" | .examples[0].digest="different"' "$GS_ROOT/features/one/snapshots/post-test.json" > "$GS_ROOT/after.json"
assert_fail 'failed to passed transition cannot hide digest edit' 1 gs_run compare "$GS_ROOT/before.json" "$GS_ROOT/after.json" post-impl
jq 'del(.protected_files)' "$GS_ROOT/features/one/snapshots/post-test.json" > "$GS_ROOT/after.json"
assert_fail 'Go snapshots missing protected inventory fail closed' 1 gs_run compare "$GS_ROOT/features/one/snapshots/post-test.json" "$GS_ROOT/after.json" post-impl
rm -rf "$GS_ROOT"
