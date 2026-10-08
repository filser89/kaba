#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
export GOCACHE="${GOCACHE:-${TMPDIR:-/tmp}/kaba-go-build}"
GS_RUNNER="$SCRIPT_DIR/../scripts/test-runner.sh"
GS_REPO="$(mktemp -d)"
GS_TEMPS="$(mktemp -d)"
git -C "$GS_REPO" init -q
mkdir -p "$GS_REPO/.kaba" "$GS_REPO/features/one/snapshots" "$GS_REPO/testdata/kaba/one"
cat > "$GS_REPO/.kaba/config.yml" <<'CONFIG'
test_runner: go
test_command: go test ./...
feature_dir: features/
linter_command: "true"
test_write_allow: ["**/*_test.go", "**/testdata/**", "features/**"]
test_write_exclude: []
implement_write_allow: ["**"]
implement_write_exclude: ["**/*_test.go", "**/testdata/**"]
CONFIG
printf 'module example/scaffold\n\ngo 1.23\n' > "$GS_REPO/go.mod"
cp "$SCRIPT_DIR/fixtures/go-scaffold/pay.go" "$GS_REPO/pay.go"
printf 'package demo\nimport "testing"\nfunc TestExisting(t *testing.T){if OldBehavior()!=42{t.Fatal("old behavior")}}\n' > "$GS_REPO/pay_test.go"
gs_run() { (cd "$GS_REPO" && TMPDIR="$GS_TEMPS" FEATURE_DIR="$GS_REPO/features/one" bash "$GS_RUNNER" "$@"); }
gs_helper() { (cd "$SCRIPT_DIR/../scripts/go" && go run . scaffold --root "$GS_REPO" --feature "$GS_REPO/features/one" --output "$GS_OUTPUT" --permission-helper "$SCRIPT_DIR/../scripts/path-permissions.sh" "$@"); }
# Existing Go source is not restricted to the placeholder declaration grammar.
printf 'package demo; type Embedded[T any] struct { Value T }; type Old struct { _ [8]byte; Embedded[int] };func OldBehavior() int{return 42}\n' > "$GS_REPO/pay.go"
assert_ok "ordinary blank and generic embedded fields pass baseline" gs_run run --phase baseline
assert_ok "ordinary blank and generic embedded fields pass without scaffolds" gs_run run --phase post-test
# A syntactically minimal declaration must not rebind existing builtin calls.
printf 'package demo;func OldBehavior() int{return len([]int{1,2,3})}\n' > "$GS_REPO/pay.go"
printf 'package demo;import "testing";func TestExisting(t *testing.T){if OldBehavior()!=3{t.Fatal("builtin changed")}}\n' > "$GS_REPO/pay_test.go"
printf 'package demo;func len(x []int) int{return 0}\n' > "$GS_REPO/testdata/kaba/one/api.go"
assert_ok "existing builtin behavior passes real baseline" gs_run run --phase baseline
assert_fail "scaffold cannot shadow builtin and fabricate existing red" 1 gs_run run --phase post-test
assert_stderr_match "builtin shadow rejection identifies scope collision" 'shadows predeclared identifier len' gs_run run --phase post-test
rm "$GS_REPO/testdata/kaba/one/api.go"
cp "$SCRIPT_DIR/fixtures/go-scaffold/pay.go" "$GS_REPO/pay.go"
printf 'package demo\nimport "testing"\nfunc TestExisting(t *testing.T){if OldBehavior()!=42{t.Fatal("old behavior")}}\n' > "$GS_REPO/pay_test.go"
gs_baseline="$(gs_run run --phase baseline)"
printf '%s' "$gs_baseline" | jq '. + {version:2,runner_schema:.schema,metadata:{name:"baseline"}}' > "$GS_REPO/features/one/snapshots/baseline.json"
cp "$SCRIPT_DIR/fixtures/go-scaffold/pay_test.go" "$GS_REPO/pay_test.go"
cp "$SCRIPT_DIR/fixtures/go-scaffold/api.go" "$GS_REPO/testdata/kaba/one/api.go"
gs_production_hash="$(git hash-object "$GS_REPO/pay.go")"
gs_test_hash="$(git hash-object "$GS_REPO/pay_test.go")"
gs_scaffold_hash="$(git hash-object "$GS_REPO/testdata/kaba/one/api.go")"
assert_fail "missing API without overlay is compilation failure" 1 gs_run run --phase baseline
assert_ok "validated declarations execute real post-test assertions" gs_run run --phase post-test
gs_red="$(gs_run run --phase post-test 2>/dev/null || true)"
assert_eq "missing type method field yield actual named red" 'TestMissingField,TestMissingMethod,TestMissingType' "$(printf '%s' "$gs_red" | jq -r '[.examples[]|select(.status=="failed")|.test_name]|sort|join(",")')"
assert_eq "old behavior and zero accidental pass are real passes" 'TestExisting,TestZero' "$(printf '%s' "$gs_red" | jq -r '[.examples[]|select(.status=="passed")|.test_name]|sort|join(",")')"
assert_eq "scaffold metadata names protected feature source" 'testdata/kaba/one/api.go' "$(printf '%s' "$gs_red" | jq -r '.scaffolds[0].path')"
assert_eq "temporary capture preserves production bytes" "$gs_production_hash" "$(git hash-object "$GS_REPO/pay.go")"
assert_eq "runner cleans overlays after successful red capture" 0 "$(find "$GS_TEMPS" -mindepth 1 -maxdepth 1 -name 'kaba-go-run.*' | wc -l | tr -d ' ')"
printf '%s' "$gs_red" | jq '. + {version:2,runner_schema:.schema,metadata:{name:"post-test"}}' > "$GS_REPO/features/one/snapshots/post-test.json"
printf '{"version":3,"entries":[{"action":"PIN","file":"pay_test.go","description":"TestZero","expected_landing":"passed"}]}\n' > "$GS_REPO/features/one/test-plan.json"
gs_compare() { (cd "$GS_REPO" && FEATURE_DIR="$GS_REPO/features/one" bash "$SCRIPT_DIR/../scripts/snapshot-tests.sh" compare post-test); }
gs_validate() { (cd "$GS_REPO" && FEATURE_DIR="$GS_REPO/features/one" bash "$SCRIPT_DIR/../scripts/snapshot-tests.sh" validate-plan); }
assert_ok "overlay-dependent PIN plan is structurally valid" gs_validate
assert_fail "actual scaffold-induced zero PIN is rejected" 1 gs_compare
assert_stdout_match "overlay PIN rejection explains real-code proof" 'PIN.*overlay|PIN.*scaffold' gs_compare
assert_fail "post-impl does not use surviving scaffold sources" 1 gs_run run --phase post-impl
assert_eq "runner cleans temps after compilation errors" 0 "$(find "$GS_TEMPS" -mindepth 1 -maxdepth 1 -name 'kaba-go-run.*' | wc -l | tr -d ' ')"
# Real declarations make the same locked test bytes green with no scaffolding.
cat > "$GS_REPO/pay.go" <<'REAL'
package demo
type Old struct { Original int; Added int }
func OldBehavior() int { return 42 }
type Need struct { Value int }
func New() Need { return Need{Value:9} }
func (o Old) Missing() int { return 9 }
func NewOld() Old { return Old{Added:9} }
func Zero() int { return 0 }
REAL
assert_ok "same locked tests run green against real implementation" gs_run run --phase post-impl
gs_green="$(gs_run run --phase post-impl 2>/dev/null || true)"
assert_eq "real green has no overlay or scaffold metadata" '0,0,5' "$(printf '%s' "$gs_green" | jq -r '[(.scaffolds|length),(.overlay_packages|length),([.examples[]|select(.status=="passed")]|length)]|join(",")')"
assert_eq "locked identities and digests match red to real green" "$(printf '%s' "$gs_red" | jq -c '[.examples[]|{id,digest}]|sort_by(.id)')" "$(printf '%s' "$gs_green" | jq -c '[.examples[]|{id,digest}]|sort_by(.id)')"
assert_eq "implementation preserves locked test bytes" "$gs_test_hash" "$(git hash-object "$GS_REPO/pay_test.go")"
assert_eq "implementation preserves scaffold source bytes" "$gs_scaffold_hash" "$(git hash-object "$GS_REPO/testdata/kaba/one/api.go")"
assert_fail "post-test rejects stale scaffold against implemented API" 1 gs_run run --phase post-test
assert_eq "runner cleans temps after scaffold validation failure" 0 "$(find "$GS_TEMPS" -mindepth 1 -maxdepth 1 -name 'kaba-go-run.*' | wc -l | tr -d ' ')"
cp "$SCRIPT_DIR/fixtures/go-scaffold/pay.go" "$GS_REPO/pay.go"
printf 'package demo; func OldBehavior() int { return 0 }\n' > "$GS_REPO/testdata/kaba/one/api.go"
assert_fail "whole production behavior replacement is forbidden" 1 gs_run run --phase post-test
printf 'package demo; func New() int { panic("red") }\n' > "$GS_REPO/testdata/kaba/one/api.go"
assert_fail "panic placeholder cannot fabricate red" 1 gs_run run --phase post-test
printf 'package demo; func New() int { return 1 }\n' > "$GS_REPO/testdata/kaba/one/api.go"
assert_fail "business return value is forbidden in scaffold" 1 gs_run run --phase post-test
printf 'package demo; func New() int { return 0 };func New() int { return 0 }\n' > "$GS_REPO/testdata/kaba/one/api.go"
assert_fail "duplicate scaffold declarations are rejected" 1 gs_run run --phase post-test
cp "$SCRIPT_DIR/fixtures/go-scaffold/api.go" "$GS_REPO/testdata/kaba/one/api.go"
cat > "$GS_REPO/pay_test.go" <<'PANIC'
package demo
import "testing"
func TestAbort(t *testing.T) { panic("package stops before later cases") }
func TestLater(t *testing.T) { if New().Value!=9 { t.Fatal("real red") } }
PANIC
assert_fail "actual scaffolded panic cannot hide later expected tests" 1 gs_run run --phase post-test
assert_eq "runner cleans temps after incomplete panic run" 0 "$(find "$GS_TEMPS" -mindepth 1 -maxdepth 1 -name 'kaba-go-run.*' | wc -l | tr -d ' ')"
GS_OUTPUT="$(mktemp -d)"
printf 'package demo; func New() int { return 0 }\n' > "$GS_REPO/testdata/kaba/one/api.go"
printf stale > "$GS_OUTPUT/stale"
assert_fail "stale temporary overlays are rejected" 1 gs_helper
rm "$GS_OUTPUT/stale"
sed 's@implement_write_exclude:.*@implement_write_exclude: ["**/*_test.go"]@' "$GS_REPO/.kaba/config.yml" > "$GS_REPO/.kaba/new.yml"
mv "$GS_REPO/.kaba/new.yml" "$GS_REPO/.kaba/config.yml"
assert_fail "shared scaffold paths are not test-owned" 1 gs_helper
sed 's@implement_write_exclude:.*@implement_write_exclude: ["**/*_test.go", "**/testdata/**"]@' "$GS_REPO/.kaba/config.yml" > "$GS_REPO/.kaba/new.yml"
mv "$GS_REPO/.kaba/new.yml" "$GS_REPO/.kaba/config.yml"
mkdir -p "$GS_REPO/selected/testdata/kaba/one" "$GS_REPO/excluded/testdata/kaba/one" "$GS_TEMPS/bin"
cat > "$GS_REPO/selected/types.go" <<'TAGS'
//go:build selected

package selected
type Old struct{}
func Existing() int { return 42 }
TAGS
printf 'package selected; import "time"; type Old struct { Added time.Time }; func Missing() int { return 0 }\n' > "$GS_REPO/selected/testdata/kaba/one/api.go"
cat > "$GS_REPO/selected/api_test.go" <<'SELECTED'
package selected
import ("testing"; "time")
func TestExisting(t *testing.T) { if Existing()!=42 { t.Fatal("tagged behavior") } }
func TestField(t *testing.T) { if (Old{Added:time.Unix(1,0)}).Added.IsZero() { t.Fatal("field import") } }
func TestMissing(t *testing.T) { if Missing()!=1 { t.Fatal("real red") } }
SELECTED
printf 'package excluded\n' > "$GS_REPO/excluded/types.go"
printf 'package excluded;func Invalid(){panic("invalid excluded scaffold")}\n' > "$GS_REPO/excluded/testdata/kaba/one/api.go"
GS_REAL_GO="$(command -v go)"; GS_GOLOG="$GS_TEMPS/go.log"; export GS_REAL_GO GS_GOLOG
cat > "$GS_TEMPS/bin/go" <<'PROXY'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GS_GOLOG"
exec "$GS_REAL_GO" "$@"
PROXY
chmod +x "$GS_TEMPS/bin/go"
sed "s@^test_command:.*@test_command: $GS_TEMPS/bin/go test -tags=selected ./selected@" "$GS_REPO/.kaba/config.yml" > "$GS_REPO/.kaba/new.yml"
mv "$GS_REPO/.kaba/new.yml" "$GS_REPO/.kaba/config.yml"
assert_ok "field imports compile in matching selected tagged package" gs_run run --phase post-test
gs_selected="$(gs_run run --phase post-test 2>/dev/null || true)"
assert_eq "unselected malformed scaffolds are not included" 'example/scaffold/selected' "$(printf '%s' "$gs_selected" | jq -r '.overlay_packages|join(",")')"
assert_eq "typed field insertion preserves tagged old behavior" 'TestExisting,TestField' "$(printf '%s' "$gs_selected" | jq -r '[.examples[]|select(.status=="passed")|.test_name]|sort|join(",")')"
assert_stdout_match "configured Go executable owns discovery with tags" 'list.*-tags selected.*./selected' cat "$GS_GOLOG"
assert_fail "helper refuses a package directory as repository root" 1 gs_helper --root "$GS_REPO/selected"
assert_fail "helper refuses features outside configured feature root" 1 gs_helper --feature "$GS_REPO/selected"
# Trapped TERM exits clean temporary overlays after the active Go child returns.
cat > "$GS_REPO/selected/api_test.go" <<'INTERRUPT'
package selected
import ("testing"; "time"; "os")
func TestSleep(t *testing.T) { if err:=os.WriteFile("started",[]byte("started"),0600);err!=nil{t.Fatal(err)};time.Sleep(2*time.Second) }
INTERRUPT
(cd "$GS_REPO" && exec env TMPDIR="$GS_OUTPUT" FEATURE_DIR="$GS_REPO/features/one" bash "$GS_RUNNER" run --phase post-test) > "$GS_REPO/interrupted.json" 2> "$GS_REPO/interrupted.err" &
gs_pid=$!; gs_wait=0
while [[ ! -f "$GS_REPO/selected/started" && "$gs_wait" -lt 100 ]]; do sleep 0.1; gs_wait=$((gs_wait+1)); done
assert_file_exists "TERM test reaches real scaffolded execution" "$GS_REPO/selected/started"
kill -TERM "$gs_pid" 2>/dev/null || true
gs_exit=0; wait "$gs_pid" || gs_exit=$?
assert_eq "runner TERM interruption reports signal exit" 143 "$gs_exit"
assert_eq "runner TERM cleanup removes scaffold directory" 0 "$(find "$GS_OUTPUT" -mindepth 1 -maxdepth 1 -name 'kaba-go-run.*' | wc -l | tr -d ' ')"
rm -rf "$GS_REPO" "$GS_TEMPS" "$GS_OUTPUT"
