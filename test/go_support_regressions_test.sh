#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
GSR_SCRIPTS="$SCRIPT_DIR/../scripts"
export GOCACHE="${GOCACHE:-/private/tmp/kaba-go-build}"
GSR_REPO="$(mktemp -d)"
git -C "$GSR_REPO" init -q
mkdir -p "$GSR_REPO/.kaba" "$GSR_REPO/features/one" "$GSR_REPO/internal/testutil/deep"
cp "$SCRIPT_DIR/fixtures/go-config.yml" "$GSR_REPO/.kaba/config.yml"
printf 'module example.com/support.test\n\ngo 1.23\n' > "$GSR_REPO/go.mod"
gsr_run() { (cd "$GSR_REPO" && FEATURE_DIR="$GSR_REPO/features/one" bash "$GSR_SCRIPTS/test-runner.sh" "$@" --phase baseline); }
gsr_snap() { (cd "$GSR_REPO" && FEATURE_DIR="$GSR_REPO/features/$gsr_feature" bash "$GSR_SCRIPTS/snapshot-tests.sh" "$@"); }
gsr_digest() { gsr_run digests | jq -er --arg name "$1" '.examples[] | select(.test_name==$name) | .digest'; }
gsr_changed() { local current; current="$(gsr_digest "$1")" && [[ -n "$2" && "$current" != "$2" ]]; }
cat > "$GSR_REPO/p_test.go" <<'GO'
package support
import("testing"; "example.com/support.test/internal/testutil")
func TestHelper(t *testing.T) { if testutil.Input() < 1 { t.Fatal("input") } }
GO
cat > "$GSR_REPO/internal/testutil/helper.go" <<'GO'
package testutil
import "example.com/support.test/internal/testutil/deep"
func Input() int { return deep.Value() }
GO
printf 'package deep\nfunc Value() int { return 1 }\n' > "$GSR_REPO/internal/testutil/deep/value.go"
gsr_before="$(gsr_digest TestHelper)"
printf 'package deep\nfunc Value() int { return 2 }\n' > "$GSR_REPO/internal/testutil/deep/value.go"
assert_ok 'transitively imported test-owned Go helper changes digest' gsr_changed TestHelper "$gsr_before"
gsr_before="$(gsr_digest TestHelper)"
printf '// ordinary comment\npackage deep\nfunc Value() int {\n return 2\n}\n' > "$GSR_REPO/internal/testutil/deep/value.go"
assert_eq 'imported support digest ignores formatting and comments' "$gsr_before" "$(gsr_digest TestHelper)"
cat > "$GSR_REPO/internal/testutil/deep/ignored.go" <<'GO'
//go:build excluded

package deep
func Ignored() int { return 3 }
GO
assert_eq 'unselected build-tag helper does not change digest' "$gsr_before" "$(gsr_digest TestHelper)"
printf '//go:build !excluded\n\npackage deep\nfunc Value() int { return 2 }\n' > "$GSR_REPO/internal/testutil/deep/value.go"
assert_ok 'active support build directives contribute to digest' gsr_changed TestHelper "$gsr_before"
printf 'package support\nfunc Production() int { return 1 }\n' > "$GSR_REPO/p.go"
gsr_before="$(gsr_digest TestHelper)"
printf 'package support\nfunc Production() int { return 2 }\n' > "$GSR_REPO/p.go"
assert_eq 'production body edits do not change test digest' "$gsr_before" "$(gsr_digest TestHelper)"
# The same green helper edit must be rejected without, and accepted with, TOUCH.
for gsr_feature in empty touch; do
  mkdir -p "$GSR_REPO/features/$gsr_feature"
  printf 'package deep\nfunc Value() int { return 1 }\n' > "$GSR_REPO/internal/testutil/deep/value.go"
  assert_ok "$gsr_feature helper baseline capture" gsr_snap capture baseline
  if [[ "$gsr_feature" == empty ]]; then
    printf '{"version":3,"entries":[]}\n' > "$GSR_REPO/features/$gsr_feature/test-plan.json"
  else
    printf '{"version":3,"entries":[{"action":"TOUCH","expected_landing":"unchanged","id":"example.com/support.test::TestHelper","file":"p_test.go","description":"TestHelper"}]}\n' > "$GSR_REPO/features/$gsr_feature/test-plan.json"
  fi
  assert_ok "$gsr_feature helper plan validation" gsr_snap validate-plan
  printf 'package deep\nfunc Value() int { return 2 }\n' > "$GSR_REPO/internal/testutil/deep/value.go"
  assert_ok "$gsr_feature helper post-test capture" gsr_snap capture post-test
  if [[ "$gsr_feature" == empty ]]; then
    assert_fail 'empty plan rejects imported helper digest drift' 1 gsr_snap compare post-test
  else
    assert_ok 'planned TOUCH permits imported helper digest drift' gsr_snap compare post-test
    assert_stdout_match 'planned helper TOUCH is used' 'Drifted: +1 .*allowlisted content edits' gsr_snap compare post-test
  fi
done
cat > "$GSR_REPO/p_test.go" <<'GO'
package support
import "testing"
func setup(t *testing.T) int { t.Helper(); return 1 }
func TestSetup(t *testing.T) { value := setup(t); if value != 1 { t.Fatal(value) } }
GO
assert_ok 'assigned ordinary setup helper return value is supported' gsr_run run
cat > "$GSR_REPO/p_test.go" <<'GO'
package support
import "testing"
var _ = initialize()
func initialize() int { Production(); return 1 }
func TestInternal(t *testing.T) { if Production() < 1 { t.Fatal("production") } }
GO
cat > "$GSR_REPO/external_test.go" <<'GO'
package support_test
import ("testing"; "os")
func TestMain(m *testing.M) { os.Exit(m.Run()) }
func TestExternal(t *testing.T) {}
GO
gsr_internal="$(gsr_digest TestInternal)"; gsr_external="$(gsr_digest TestExternal)"
sed 's/return 1/return 2/' "$GSR_REPO/p_test.go" > "$GSR_REPO/edit.tmp"
mv "$GSR_REPO/edit.tmp" "$GSR_REPO/p_test.go"
assert_ok 'implicit initializer helper affects internal tests' gsr_changed TestInternal "$gsr_internal"
assert_ok 'implicit initializer helper affects external tests' gsr_changed TestExternal "$gsr_external"
gsr_internal="$(gsr_digest TestInternal)"
sed 's/os.Exit(m.Run())/println("setup"); os.Exit(m.Run())/' "$GSR_REPO/external_test.go" > "$GSR_REPO/edit.tmp"
mv "$GSR_REPO/edit.tmp" "$GSR_REPO/external_test.go"
assert_ok 'external TestMain affects internal test digests' gsr_changed TestInternal "$gsr_internal"
gsr_external="$(gsr_digest TestExternal)"
printf '\nfunc init() { println("internal init") }\n' >> "$GSR_REPO/p_test.go"
assert_ok 'internal init affects external test digests' gsr_changed TestExternal "$gsr_external"
printf '\nvar _ interface{} = (*int)(nil)\nvar _ interface{} = (*string)(nil)\n' >> "$GSR_REPO/p_test.go"
printf '\nvar _ interface{} = (*bool)(nil)\n' > "$GSR_REPO/assertions.tmp"
{ printf 'package support\n'; cat "$GSR_REPO/assertions.tmp"; } > "$GSR_REPO/assertions_test.go"
assert_ok 'multiple blank compile assertions have distinct identities' gsr_run run
printf '\ntype _ int\ntype _ bool\n' >> "$GSR_REPO/p_test.go"
printf '\ntype _ string\n' >> "$GSR_REPO/assertions_test.go"
assert_ok 'blank type declarations do not collide across test files' gsr_run run
printf '\nfunc _() {}\nfunc _() {}\n' >> "$GSR_REPO/p_test.go"
printf '\nfunc _() {}\n' >> "$GSR_REPO/assertions_test.go"
assert_ok 'blank function declarations do not collide across test files' gsr_run run
printf '\ntype blankReceiver int\nfunc (blankReceiver) _() {}\n' >> "$GSR_REPO/p_test.go"
printf '\nfunc (blankReceiver) _() {}\n' >> "$GSR_REPO/assertions_test.go"
assert_ok 'blank method declarations do not collide across test files' gsr_run run
rm -f "$GSR_REPO/external_test.go" "$GSR_REPO/assertions_test.go"
cat > "$GSR_REPO/.kaba/config.yml" <<'YAML'
test_runner: go
test_command: go test ./...
feature_dir: features/
linter_command: "true"
test_write_allow: ["**/*_test.go", "local_support.go", "internal/testutil/**", "features/**"]
test_write_exclude: []
implement_write_allow: ["**"]
implement_write_exclude: ["**/*_test.go", "local_support.go", "internal/testutil/**"]
YAML
printf 'package support\nfunc localValue() int { return 1 }\n' > "$GSR_REPO/local_support.go"
printf 'package support\nimport "testing"\nfunc TestLocal(t *testing.T) { if localValue() < 1 { t.Fatal("local") } }\n' > "$GSR_REPO/p_test.go"
gsr_before="$(gsr_digest TestLocal)"
printf 'package support\nfunc localValue() int { return 2 }\n' > "$GSR_REPO/local_support.go"
assert_ok 'ordinary same-package test-owned helper affects digest' gsr_changed TestLocal "$gsr_before"
printf 'package support\nfunc LocalValue() int { return 1 }\n' > "$GSR_REPO/local_support.go"
printf 'package support_test\nimport ("testing"; p "example.com/support.test")\nfunc TestExternalLocal(t *testing.T) { if p.LocalValue() < 1 { t.Fatal("local") } }\n' > "$GSR_REPO/p_test.go"
gsr_before="$(gsr_digest TestExternalLocal)"
printf 'package support\nfunc LocalValue() int { return 2 }\n' > "$GSR_REPO/local_support.go"
assert_ok 'external package depends on ordinary local test-owned helper' gsr_changed TestExternalLocal "$gsr_before"
cat > "$GSR_REPO/p_test.go" <<'GO'
package support
import ("testing"; "fmt")
type formatter struct{}
func (formatter) String() string { return "one" }
func TestImplicitMethod(t *testing.T) { if len(fmt.Sprint(formatter{})) != 3 { t.Fatal("format") } }
GO
assert_ok 'implicit interface method fixture executes real behavior' gsr_run run
gsr_before="$(gsr_digest TestImplicitMethod)"
sed 's/return "one"/return "two"/' "$GSR_REPO/p_test.go" > "$GSR_REPO/edit.tmp"
mv "$GSR_REPO/edit.tmp" "$GSR_REPO/p_test.go"
assert_ok 'implicitly invoked test fake method changes dependent digest' gsr_changed TestImplicitMethod "$gsr_before"
for gsr_body in 'alias:=t;alias.Run("hidden",func(t *testing.T){})' 'run:=t.Run;run("hidden",func(t *testing.T){})' 'if true {t.Run("hidden",func(t *testing.T){})}'; do
  printf 'package support\nimport "testing"\nfunc TestHidden(t *testing.T){ %s }\n' "$gsr_body" > "$GSR_REPO/p_test.go"
  assert_fail 'unsupported alias or conditional registration still fails' 1 gsr_run identities
done
rm -rf "$GSR_REPO"
