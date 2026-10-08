#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
GC_SCRIPT="$SCRIPT_DIR/../scripts/cleanup-tests.sh"
GC_SNAP="$SCRIPT_DIR/../scripts/snapshot-tests.sh"
GC_ROOT="$(mktemp -d)"
git -C "$GC_ROOT" init -q
mkdir -p "$GC_ROOT/.kaba" "$GC_ROOT/features/one/snapshots" "$GC_ROOT/testdata/kaba/one"
cat > "$GC_ROOT/.kaba/config.yml" <<'CFG'
test_runner: go
test_command: go test ./...
linter_command: "test ! -e quality-fail"
feature_dir: features/
test_write_allow: ["**/*_test.go", "testdata/**", "features/**"]
test_write_exclude: []
implement_write_allow: ["**"]
implement_write_exclude: ["**/*_test.go", "testdata/**"]
CFG
printf 'module cleanup.test\n\ngo 1.23\n' > "$GC_ROOT/go.mod"
printf 'package cleanup\nimport "testing"\nfunc TestGone(t *testing.T){t.Skip("REMOVED by one")}\nfunc TestKeep(t *testing.T){}\n' > "$GC_ROOT/one_test.go"
printf unrelated > "$GC_ROOT/unrelated.txt"
gc_run() { (cd "$GC_ROOT" && GOCACHE="${TMPDIR:-/tmp}/kaba-go-build" FEATURE_DIR="$GC_ROOT/features/one" bash "$GC_SCRIPT"); }
gc_capture() { (cd "$GC_ROOT" && GOCACHE="${TMPDIR:-/tmp}/kaba-go-build" FEATURE_DIR="$GC_ROOT/features/one" bash "$GC_SNAP" capture "$1"); }
assert_fail 'cleanup refuses incomplete feature snapshots' 1 gc_run
assert_ok 'cleanup fixture captures baseline' gc_capture baseline
assert_ok 'cleanup fixture captures post-test' gc_capture post-test
printf '{"version":3,"entries":[]}' > "$GC_ROOT/features/one/test-plan.json"
cp "$GC_ROOT/features/one/test-plan.json" "$GC_ROOT/features/one/snapshots/test-plan.lock.json"
gc_compare() { (cd "$GC_ROOT" && FEATURE_DIR="$GC_ROOT/features/one" bash "$GC_SNAP" compare post-test); }
assert_ok 'cleanup fixture validates post-test requirements' gc_compare
assert_ok 'cleanup fixture captures post-impl' gc_capture post-impl
git -C "$GC_ROOT" add .
git -C "$GC_ROOT" -c user.name=Test -c user.email=test@example.test commit -qm fixture
printf implement > "$GC_ROOT/.kaba/session-lock"
assert_fail 'cleanup refuses implementation lock' 1 gc_run
rm "$GC_ROOT/.kaba/session-lock"
printf '\n' >> "$GC_ROOT/one_test.go"
assert_fail 'cleanup refuses dirty affected source' 1 gc_run
git -C "$GC_ROOT" checkout -- one_test.go
printf fail > "$GC_ROOT/quality-fail"
assert_fail 'present postimpl snapshot cannot bypass quality gate' 1 gc_run
assert_stdout_match 'quality rejection leaves removal intact' TestGone cat "$GC_ROOT/one_test.go"
rm "$GC_ROOT/quality-fail"
assert_ok 'cleanup deletes exact observed pending function' gc_run
assert_eq 'cleanup preserves unrelated bytes' unrelated "$(cat "$GC_ROOT/unrelated.txt")"
assert_eq 'cleanup keeps only neighbor identity' 0 "$(rg -c TestGone "$GC_ROOT/one_test.go" || printf 0)"
assert_ok 'repeated successful cleanup is a no-op' gc_run
rm -rf "$GC_ROOT"
# Retained scaffold sources represent a validated post-test overlay after real code lands.
gc_scaffold_fixture() {
  GC_ROOT="$(mktemp -d)"
  git -C "$GC_ROOT" init -q
  mkdir -p "$GC_ROOT/.kaba" "$GC_ROOT/features/one/snapshots" "$GC_ROOT/testdata/kaba/one"
  cat > "$GC_ROOT/.kaba/config.yml" <<'CFG'
test_runner: go
test_command: go test ./...
linter_command: "true"
feature_dir: features/
test_write_allow: ["**/*_test.go", "testdata/**", "features/**"]
test_write_exclude: []
implement_write_allow: ["**"]
implement_write_exclude: ["**/*_test.go", "testdata/**"]
CFG
  printf 'module cleanup.test\n\ngo 1.23\n' > "$GC_ROOT/go.mod"
  printf 'package cleanup\nimport "testing"\nfunc TestKeep(t *testing.T){}\n' > "$GC_ROOT/one_test.go"
  printf 'package cleanup\ntype Missing struct{}\n' > "$GC_ROOT/testdata/kaba/one/api.go"
  printf unrelated > "$GC_ROOT/unrelated.txt"
  gc_capture post-impl >/dev/null || return
  jq '.metadata.name="baseline"' "$GC_ROOT/features/one/snapshots/post-impl.json" > "$GC_ROOT/features/one/snapshots/baseline.json"
  local hash
  hash="$(shasum -a 256 "$GC_ROOT/testdata/kaba/one/api.go")"; hash="${hash%% *}"
  jq --arg hash "$hash" '.metadata.name="post-test" | .implementation_required=[] | .scaffolds=[{path:"testdata/kaba/one/api.go",sha256:$hash,package:"cleanup.test"}]' "$GC_ROOT/features/one/snapshots/post-impl.json" > "$GC_ROOT/features/one/snapshots/post-test.json"
  jq '{version:1,feature:"one",files:.scaffolds}' "$GC_ROOT/features/one/snapshots/post-test.json" > "$GC_ROOT/features/one/snapshots/scaffolds.json"
  printf '{"version":3,"entries":[]}' > "$GC_ROOT/features/one/test-plan.json"
  cp "$GC_ROOT/features/one/test-plan.json" "$GC_ROOT/features/one/snapshots/test-plan.lock.json"
  git -C "$GC_ROOT" add .
  git -C "$GC_ROOT" -c user.name=Test -c user.email=test@example.test commit -qm fixture
}
gc_scaffold_fixture
assert_ok 'scaffold-only cleanup keeps exact test identities' gc_run
assert_eq 'successful cleanup removes recorded scaffold' false "$([[ -f "$GC_ROOT/testdata/kaba/one/api.go" ]] && echo true || echo false)"
assert_eq 'successful cleanup consumes manifest' false "$([[ -f "$GC_ROOT/features/one/snapshots/scaffolds.json" ]] && echo true || echo false)"
assert_eq 'scaffold cleanup preserves unrelated bytes' unrelated "$(cat "$GC_ROOT/unrelated.txt")"
assert_ok 'scaffold-only cleanup repeats without reconstruction' gc_run
rm -rf "$GC_ROOT"
gc_scaffold_fixture
sed -i '' 's/linter_command: "true"/linter_command: "test -e testdata\/kaba\/one\/api.go"/' "$GC_ROOT/.kaba/config.yml"
GC_BEFORE="$(git hash-object "$GC_ROOT/testdata/kaba/one/api.go")"
# Noncanonical formatting must survive rollback byte-for-byte.
jq -c . "$GC_ROOT/features/one/snapshots/scaffolds.json" > "$GC_ROOT/manifest-tmp"
mv "$GC_ROOT/manifest-tmp" "$GC_ROOT/features/one/snapshots/scaffolds.json"
GC_MANIFEST="$(git hash-object "$GC_ROOT/features/one/snapshots/scaffolds.json")"
assert_fail 'postdeletion quality failure triggers exact rollback' 1 gc_run
assert_eq 'rollback restores exact scaffold bytes' "$GC_BEFORE" "$(git hash-object "$GC_ROOT/testdata/kaba/one/api.go")"
assert_eq 'rollback restores exact manifest bytes' "$GC_MANIFEST" "$(git hash-object "$GC_ROOT/features/one/snapshots/scaffolds.json")"
assert_eq 'rollback preserves unrelated bytes' unrelated "$(cat "$GC_ROOT/unrelated.txt")"
rm -rf "$GC_ROOT"
gc_scaffold_fixture
jq '.files[0].path="unrelated.txt"' "$GC_ROOT/features/one/snapshots/scaffolds.json" > "$GC_ROOT/bad.json"
mv "$GC_ROOT/bad.json" "$GC_ROOT/features/one/snapshots/scaffolds.json"
assert_fail 'manifest cannot grant production deletion permission' 1 gc_run
assert_eq 'unsafe manifest leaves unrelated bytes intact' unrelated "$(cat "$GC_ROOT/unrelated.txt")"
rm -rf "$GC_ROOT"
gc_scaffold_fixture
printf changed >> "$GC_ROOT/testdata/kaba/one/api.go"
assert_fail 'changed scaffold hash is refused before deletion' 1 gc_run
assert_file_exists 'changed scaffold is retained' "$GC_ROOT/testdata/kaba/one/api.go"
rm -rf "$GC_ROOT"

gc_scaffold_fixture
printf 'package cleanup\nimport "testing"\nfunc TestKeep(t *testing.T){t.Fatal("real failure")}\n' > "$GC_ROOT/one_test.go"
assert_fail 'present snapshots cannot bypass fresh suite failure' 1 gc_run
assert_file_exists 'fresh failure keeps scaffold untouched' "$GC_ROOT/testdata/kaba/one/api.go"
rm -rf "$GC_ROOT"
gc_scaffold_fixture
printf 'package cleanup\nimport "testing"\nfunc TestKeep(t *testing.T){}\nfunc TestExtra(t *testing.T){}\n' > "$GC_ROOT/one_test.go"
git -C "$GC_ROOT" add one_test.go
git -C "$GC_ROOT" -c user.name=Test -c user.email=test@example.test commit -qm 'extra source'
assert_fail 'fresh extra identity cannot bypass locked comparison' 1 gc_run
assert_file_exists 'identity drift keeps scaffold untouched' "$GC_ROOT/testdata/kaba/one/api.go"
rm -rf "$GC_ROOT"
# Full real suite fails only after deletion; both source and scaffold must restore.
gc_scaffold_fixture
printf 'package cleanup\nimport "testing"\nimport "os"\nfunc TestGone(t *testing.T){t.Skip("REMOVED by one")}\nfunc TestKeep(t *testing.T){if _,err:=os.Stat("testdata/kaba/one/api.go");err!=nil{t.Fatal(err)}}\n' > "$GC_ROOT/one_test.go"
gc_capture post-impl >/dev/null
jq '.metadata.name="baseline"' "$GC_ROOT/features/one/snapshots/post-impl.json" > "$GC_ROOT/features/one/snapshots/baseline.json"
GC_SCAFFOLD_HASH="$(shasum -a 256 "$GC_ROOT/testdata/kaba/one/api.go")";GC_SCAFFOLD_HASH="${GC_SCAFFOLD_HASH%% *}"
jq --arg hash "$GC_SCAFFOLD_HASH" '.metadata.name="post-test" | .implementation_required=[] | .scaffolds=[{path:"testdata/kaba/one/api.go",sha256:$hash,package:"cleanup.test"}]' "$GC_ROOT/features/one/snapshots/post-impl.json" > "$GC_ROOT/features/one/snapshots/post-test.json"
git -C "$GC_ROOT" add .
git -C "$GC_ROOT" -c user.name=Test -c user.email=test@example.test commit -qm 'verification fixture'
GC_SOURCE_HASH="$(git hash-object "$GC_ROOT/one_test.go")"
GC_MANIFEST="$(git hash-object "$GC_ROOT/features/one/snapshots/scaffolds.json")"
assert_fail 'postdeletion real suite failure rolls back partial mutation' 1 gc_run
assert_eq 'real failure restores exact deleted function bytes' "$GC_SOURCE_HASH" "$(git hash-object "$GC_ROOT/one_test.go")"
assert_eq 'real failure restores exact deleted scaffold bytes' "$GC_SCAFFOLD_HASH" "$(shasum -a 256 "$GC_ROOT/testdata/kaba/one/api.go" | awk '{print $1}')"
assert_eq 'real failure restores exact manifest bytes' "$GC_MANIFEST" "$(git hash-object "$GC_ROOT/features/one/snapshots/scaffolds.json")"
assert_eq 'real failure keeps unrelated contents' unrelated "$(cat "$GC_ROOT/unrelated.txt")"
rm -rf "$GC_ROOT"
