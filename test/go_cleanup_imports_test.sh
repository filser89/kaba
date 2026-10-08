#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
GCI_SCRIPTS="$SCRIPT_DIR/../scripts"
GCI_ROOT="$(mktemp -d)"
export GOCACHE="${TMPDIR:-/tmp}/kaba-go-build"
git -C "$GCI_ROOT" init -q
mkdir -p "$GCI_ROOT/.kaba" "$GCI_ROOT/features/one/snapshots" "$GCI_ROOT/differentpath"
printf 'module imports.test\n\ngo 1.23\n' > "$GCI_ROOT/go.mod"
cat > "$GCI_ROOT/.kaba/config.yml" <<'CFG'
test_runner: go
test_command: go test -tags selected ./...
linter_command: "true"
feature_dir: features/
test_write_allow: ["**/*_test.go", "features/**"]
test_write_exclude: []
implement_write_allow: ["**"]
implement_write_exclude: ["**/*_test.go"]
CFG
cat > "$GCI_ROOT/differentpath/selected.go" <<'GO'
//go:build selected

package actualname
const Value = 1
GO
cat > "$GCI_ROOT/differentpath/default.go" <<'GO'
//go:build !selected

package othername
const Value = 2
GO
cat > "$GCI_ROOT/imports_test.go" <<'GO'
package imports

import (
  "testing"
  "net/http" // removed with the only referencing function
  alias "strings"
  _ "image/png" // side effects survive
  "imports.test/differentpath"
)

//go:noinline
func untouched( ) string { return alias.TrimSpace(" keep ") }
func TestGoneHTTP(t *testing.T){t.Skip("REMOVED by one"); _ = http.MethodGet}
func TestGonePackage(t *testing.T){t.Skip("REMOVED by one"); _ = actualname.Value}
func TestKeep(t *testing.T){http := struct{ MethodGet string }{}; _ = http.MethodGet; if untouched() != "keep" {t.Fatal("helper changed")}}
GO
cat > "$GCI_ROOT/sole_test.go" <<'GO'
package imports
import (
//line original_test.go:20
 "testing"
)
func TestSole(t *testing.T){t.Skip("REMOVED by one")}
GO
cat > "$GCI_ROOT/sub_test.go" <<'GO'
package imports
import (old "net/url" /* retain this comment */; "testing"; . "math"; keepmath "math")
func TestSub(t *testing.T){
 t.Run("gone",func(t *testing.T){t.Skip("REMOVED by one"); _ = old.URL{}; _ = Abs(-1)})
 t.Run("keep",func(t *testing.T){_ = keepmath.Abs(-1)})
}
GO
cat > "$GCI_ROOT/dot_test.go" <<'GO'
package imports
import "testing"
import . "strings"
import "imports.test/differentpath"
func TestDotGone(t *testing.T){t.Skip("REMOVED by one"); _ = TrimSpace(" old ")}
func TestDotKeep(t *testing.T){if ToUpper("ok") != "OK" || actualname.Value != 1 {t.Fatal("dot import lost")}}
GO
cat > "$GCI_ROOT/row_test.go" <<'GO'
package imports
import "testing"
import "net/http/httptest"
func TestRows(t *testing.T){
 for _,tc:=range []struct{name,removedBy string; value any}{
  {name:"gone",removedBy:"one",value:httptest.NewRecorder()},
  {name:"keep"},
 }{
  t.Run(tc.name,func(t *testing.T){if tc.removedBy!=""{t.Skip("REMOVED by "+tc.removedBy)}})
 }
}
GO
# Hand-authored expected bytes: cleanup must only delete exact test/import spans.
cat > "$GCI_ROOT/expected-imports" <<'GO'
package imports

import (
  "testing"
   // removed with the only referencing function
  alias "strings"
  _ "image/png" // side effects survive
  
)

//go:noinline
func untouched( ) string { return alias.TrimSpace(" keep ") }


func TestKeep(t *testing.T){http := struct{ MethodGet string }{}; _ = http.MethodGet; if untouched() != "keep" {t.Fatal("helper changed")}}
GO
cat > "$GCI_ROOT/expected-sole" <<'GO'
package imports
import (
//line original_test.go:20
 
)

GO
gci_capture() { (cd "$GCI_ROOT" && FEATURE_DIR="$GCI_ROOT/features/one" bash "$GCI_SCRIPTS/snapshot-tests.sh" capture "$1"); }
gci_compare_post_test() { (cd "$GCI_ROOT" && FEATURE_DIR="$GCI_ROOT/features/one" bash "$GCI_SCRIPTS/snapshot-tests.sh" compare post-test); }
gci_cleanup() { (cd "$GCI_ROOT" && FEATURE_DIR="$GCI_ROOT/features/one" bash "$GCI_SCRIPTS/cleanup-tests.sh"); }
gci_plan() { (cd "$GCI_SCRIPTS/go" && go run . cleanup --root "$GCI_ROOT" --feature one --results "$GCI_ROOT/before.json" --output "$GCI_ROOT/plan.json"); }
gci_compile() { (cd "$GCI_ROOT" && go test -tags selected -count=1 ./...) > "$GCI_ROOT/compile.log" 2>&1; }
gci_apply_plan() {
 local i=0 path
 while IFS= read -r path; do
  jq -j --argjson i "$i" '.files[$i].content' "$GCI_ROOT/plan.json" > "$GCI_ROOT/$path"
  i=$((i+1))
 done < <(jq -r '.files[].path' "$GCI_ROOT/plan.json")
}
assert_ok 'import cleanup fixture compiles before deletion' gci_compile
(cd "$GCI_ROOT" && bash "$GCI_SCRIPTS/test-runner.sh" run --phase cleanup) > "$GCI_ROOT/before.json"
assert_ok 'import cleanup produces a command-boundary plan' gci_plan
assert_eq 'plan removes only six marked identities' '["imports.test::TestDotGone","imports.test::TestGoneHTTP","imports.test::TestGonePackage","imports.test::TestRows/gone","imports.test::TestSole","imports.test::TestSub/gone"]' "$(jq -c .removed "$GCI_ROOT/plan.json")"
git -C "$GCI_ROOT" add '*_test.go'
# Fixture commits are isolated temporary repositories, never the task repository.
git -C "$GCI_ROOT" -c user.name=Test -c user.email=test@example.test commit -qm fixture
gci_apply_plan
assert_ok 'generated cleanup source really compiles' gci_compile
if [[ "$KABA_TEST_FAIL" -gt 0 ]]; then cat "$GCI_ROOT/compile.log"; fi
assert_ok 'import deletion preserves all unaffected source bytes' cmp "$GCI_ROOT/expected-imports" "$GCI_ROOT/imports_test.go"
assert_ok 'sole-test deletion preserves import-block directives' cmp "$GCI_ROOT/expected-sole" "$GCI_ROOT/sole_test.go"
git -C "$GCI_ROOT" checkout -- '*_test.go'
assert_ok 'import fixture captures baseline' gci_capture baseline
assert_ok 'import fixture captures post-test' gci_capture post-test
printf '{"version":3,"entries":[]}' > "$GCI_ROOT/features/one/test-plan.json"
cp "$GCI_ROOT/features/one/test-plan.json" "$GCI_ROOT/features/one/snapshots/test-plan.lock.json"
assert_ok 'import fixture validates post-test obligations' gci_compare_post_test
assert_ok 'import fixture captures post-impl' gci_capture post-impl
git -C "$GCI_ROOT" add .
git -C "$GCI_ROOT" -c user.name=Test -c user.email=test@example.test commit -qm snapshots
assert_ok 'public cleanup handles newly unused imports' gci_cleanup
assert_eq 'public cleanup records exact remaining identities' '["imports.test::TestDotKeep","imports.test::TestKeep","imports.test::TestRows/keep","imports.test::TestSub/keep"]' "$(jq -c '[.examples[].id]|sort' "$GCI_ROOT/features/one/snapshots/cleanup.json" 2>/dev/null || true)"
assert_ok 'public cleanup result compiles with selected build tags' gci_compile
# Repeat from the completed-feature state with a quality gate failing only after removal.
git -C "$GCI_ROOT" checkout -- '*_test.go'
rm -f "$GCI_ROOT/features/one/snapshots/cleanup.json"
sed -i '' 's/linter_command: "true"/linter_command: "grep -q TestGoneHTTP imports_test.go"/' "$GCI_ROOT/.kaba/config.yml"
GCI_HASH="$(git -C "$GCI_ROOT" hash-object imports_test.go sole_test.go sub_test.go dot_test.go row_test.go)"
GCI_OUT="$(gci_cleanup 2>&1)"; GCI_STATUS=$?
assert_eq 'postdeletion quality failure rejects cleanup' 1 "$GCI_STATUS"
assert_stdout_match 'rollback follows postdeletion quality gate' 'configured quality command failed' printf '%s' "$GCI_OUT"
assert_eq 'rollback restores exact source and import bytes' "$GCI_HASH" "$(git -C "$GCI_ROOT" hash-object imports_test.go sole_test.go sub_test.go dot_test.go row_test.go)"
rm -rf "$GCI_ROOT"
