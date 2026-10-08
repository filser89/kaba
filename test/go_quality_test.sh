#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
QUALITY="$SCRIPT_DIR/../scripts/banned-patterns.sh"
export GOCACHE="${GOCACHE:-/private/tmp/kaba-go-build}"
d="$(mktemp -d)"
git -C "$d" init -q -b master
git -C "$d" -c user.name=Test -c user.email=test@example.com commit -q --allow-empty -m fixture
mkdir -p "$d/.kaba"
cat > "$d/.kaba/config.yml" <<'YAML'
test_runner: go
test_command: go test ./...
linter_command: false
feature_dir: features/
test_write_allow: ['**/*_test.go', '**/testdata/**', 'features/**']
test_write_exclude: []
implement_write_allow: ['**']
implement_write_exclude: ['**/*_test.go', '**/testdata/**']
YAML
printf 'module example.com/quality\n\ngo 1.23\n' > "$d/go.mod"
cat > "$d/quality_test.go" <<'GO'
package quality
import ("testing"; "net/http/httptest"; "os")
func TestValid(t *testing.T) { // VAL-001
  server := httptest.NewServer(nil); defer server.Close()
  _, _ = os.ReadFile("testdata/fixture.json")
  if server.URL == "" { t.Fatal("empty url") }
}
GO
run_quality() { (cd "$d" && bash "$QUALITY" --json "$@"); }
touch "$d/quality-ok"
assert_ok 'Go quality inspects real source and permits HTTP stubs/fixtures' run_quality
assert_stdout_match 'Go report counts actual Go files' '"files_scanned": 1' run_quality
assert_stdout_match 'Go report names RSpec bans as inapplicable' 'rspec_matcher_bans.*inapplicable' run_quality
assert_ok 'red-phase source quality does not execute aggregate project command' run_quality
# Helpers without identities remain part of the selected Go test source set.
cat > "$d/helper_test.go" <<'GO'
package quality
import "testing"
func mark(t *testing.T) { t.Skipf("REMOVED by %s", "001-feature") }
GO
assert_fail 'helper-only test files cannot hide malformed removal markers' 1 run_quality
rm "$d/helper_test.go"
mkdir -p "$d/excluded"
cat > "$d/helper_test.go" <<'GO'
//go:build kaba_quality_extra

package quality
import "testing"
func mark(t *testing.T) { t.Skipf("REMOVED by %s", "001-feature") }
GO
assert_ok 'inactive tagged test helpers stay outside quality selection' run_quality
sed 's/go test \.\/\.\.\./go test -tags kaba_quality_extra .\/\.\.\./' "$d/.kaba/config.yml" > "$d/config.tmp"
mv "$d/config.tmp" "$d/.kaba/config.yml"
assert_fail 'active build tags include helper-only test marker checks' 1 run_quality
sed 's/go test -tags kaba_quality_extra/go test/' "$d/.kaba/config.yml" > "$d/config.tmp"
mv "$d/config.tmp" "$d/.kaba/config.yml"
rm "$d/helper_test.go"
cat > "$d/external_test.go" <<'GO'
package quality_test
import "testing"
func markExternal(t *testing.T) { t.Skipf("REMOVED by %s", "001-feature") }
GO
assert_fail 'external test helpers without identities receive marker checks' 1 run_quality
rm "$d/external_test.go"
cp "$d/quality_test.go" "$d/valid.source"
cat >> "$d/quality_test.go" <<'GO'
func TestRemoval(t *testing.T) { t.Skipf("REMOVED by %s", "001-feature") }
GO
assert_fail 'formatted removal reasons fail closed' 1 run_quality
cp "$d/valid.source" "$d/quality_test.go"
cat >> "$d/quality_test.go" <<'GO'
func TestRemoval(t *testing.T) { t.Skip("REMOVED by 001-feature") }
GO
assert_ok 'literal Go removal marker is supported' run_quality
cp "$d/valid.source" "$d/quality_test.go"
cat >> "$d/quality_test.go" <<'GO'
func TestTable(t *testing.T) {
 for _, tc := range []struct{name string; removedBy string}{{"old", "001-feature"}} {
  t.Run(tc.name, func(t *testing.T) { t.Skip("REMOVED by " + tc.removedBy) })
 }
}
GO
assert_fail 'unguarded table removal marker is unsupported' 1 run_quality
cp "$d/valid.source" "$d/quality_test.go"
cat >> "$d/quality_test.go" <<'GO'
func TestTable(t *testing.T) {
 for _, tc := range []struct{name string; removedBy string}{{"old", "001-feature"}, {"current", ""}} {
  t.Run(tc.name, func(t *testing.T) {
   if tc.removedBy != "" { t.Skip("REMOVED by " + tc.removedBy) }
  })
 }
}
GO
assert_ok 'guarded per-row removal marker is supported' run_quality
cp "$d/valid.source" "$d/quality_test.go"
mkdir -p "$d/features/001-feature" "$d/testdata/kaba/001-feature"
printf 'package quality\nfunc Value() int { return 42 }\n' > "$d/value.go"
printf 'package quality\nfunc Value() int { return 0 }\n' > "$d/testdata/kaba/001-feature/api.go"
run_quality_retained() { FEATURE_DIR="$d/features/001-feature" run_quality; }
assert_ok 'source quality ignores retained scaffolds after real implementation' run_quality_retained
cat >> "$d/quality_test.go" <<'GO'
func TestDynamic(t *testing.T) { t.Run(os.Getenv("CASE"), func(t *testing.T){}) }
GO
assert_fail 'unsupported Go registration cannot silently pass quality' 1 run_quality
assert_fail 'targeted Go quality still checks full selected inventory' 1 run_quality quality_test.go
rm -rf "$d"
