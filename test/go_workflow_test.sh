#!/usr/bin/env bash
# A real consumer workflow across initialization, both locks, snapshots and cleanup.
set -uo pipefail
SCRIPT_DIR="$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
GW_SCRIPTS="$(cd "$SCRIPT_DIR/../scripts" && pwd)"
GW_ROOT="$(mktemp -d)"
export GOCACHE="${GOCACHE:-${TMPDIR:-/tmp}/kaba-go-build}"
git -C "$GW_ROOT" init -q -b 001-go-workflow
gw() { (cd "$GW_ROOT" && FEATURE_DIR="$GW_ROOT/features/001-go-workflow" bash "$GW_SCRIPTS/$1" "${@:2}"); }
gw_commit() { git -C "$GW_ROOT" add . && git -C "$GW_ROOT" -c user.name=Test -c user.email=test@example.test commit -qm "$1"; }
assert_ok 'workflow initializes an explicit Go consumer' gw init-project.sh \
  --test-runner go --test-command 'go test ./...' --feature-dir features \
  --linter-command 'test ! -e quality-fail && go vet ./...' \
  --test-write-allow '**/*_test.go' --test-write-allow 'testdata/**' \
  --test-write-allow 'features/**' --test-write-exclude '' \
  --implement-write-allow '**' --implement-write-exclude '**/*_test.go' \
  --implement-write-exclude 'testdata/**'
mkdir -p "$GW_ROOT/features/001-go-workflow/snapshots" "$GW_ROOT/testdata"
printf 'module workflow.test\n\ngo 1.23\n' > "$GW_ROOT/go.mod"
printf 'package workflow\nfunc Existing() int { return 42 }\n' > "$GW_ROOT/api.go"
printf fixture > "$GW_ROOT/testdata/data.txt"
cat > "$GW_ROOT/api_test.go" <<'GO'
package workflow
import "testing"
func TestExisting(t *testing.T) { if Existing()!=42 { t.Fatal("existing behavior") } }
func TestRows(t *testing.T) {
 for _, tc := range []struct{name string; removedBy string}{
  {name:"first", removedBy:""},
  {name:"middle", removedBy:""},
  {name:"last", removedBy:""},
 } {
  t.Run(tc.name, func(t *testing.T) {
   if tc.removedBy != "" { t.Skip("REMOVED by " + tc.removedBy) }
   if Existing()!=42 { t.Fatal("existing row") }
  })
 }
}
GO
assert_ok 'workflow base consumer commits with installed hook' gw_commit baseline
assert_ok 'workflow captures real green baseline' gw snapshot-tests.sh capture baseline
printf '{"version":3,"entries":[{"action":"REMOVE","id":"workflow.test::TestRows/middle","description":"TestRows/middle","expected_landing":"pending"}]}\n' > "$GW_ROOT/features/001-go-workflow/test-plan.json"
assert_ok 'workflow validates and locks exact row removal plan' gw snapshot-tests.sh validate-plan
assert_ok 'workflow arms test ownership lock' gw session-lock.sh set test
GW_PRODUCTION="$(git hash-object "$GW_ROOT/api.go")"
sed 's/name:"middle", removedBy:""/name:"middle", removedBy:"001-go-workflow"/' "$GW_ROOT/api_test.go" > "$GW_ROOT/replacement"
mv "$GW_ROOT/replacement" "$GW_ROOT/api_test.go"
cat > "$GW_ROOT/new_test.go" <<'GO'
package workflow
import "testing"
func TestNew(t *testing.T) {
 for _, tc := range []struct{name string; want int}{
  {name:"positive",want:9},
  {name:"negative",want:9},
 } {
  t.Run(tc.name, func(t *testing.T) { if New()!=tc.want { t.Fatal("new API must return nine") } })
 }
}
GO
mkdir -p "$GW_ROOT/testdata/kaba/001-go-workflow"
printf 'package workflow\nfunc New() int { return 0 }\n' > "$GW_ROOT/testdata/kaba/001-go-workflow/api.go"
assert_fail 'workflow test lock refuses production mutation' 1 gw session-lock.sh check api.go
assert_ok 'workflow captures actual named failures through scaffold' gw snapshot-tests.sh capture post-test
assert_ok 'workflow post-test comparison accepts red and row skip' gw snapshot-tests.sh compare post-test
printf '\n// Refined compilation support during test review.\n' >> "$GW_ROOT/testdata/kaba/001-go-workflow/api.go"
assert_ok 'workflow recaptures revised scaffold during test review' gw snapshot-tests.sh capture post-test
assert_ok 'workflow revalidates revised scaffold before implementation' gw snapshot-tests.sh compare post-test
assert_eq 'workflow new named cases really fail' 2 "$(jq '[.examples[]|select(.status=="failed")]|length' "$GW_ROOT/features/001-go-workflow/snapshots/post-test.json")"
assert_eq 'workflow production remains byte-identical during tests' "$GW_PRODUCTION" "$(git hash-object "$GW_ROOT/api.go")"
assert_file_exists 'workflow persists validated scaffold manifest' "$GW_ROOT/features/001-go-workflow/snapshots/scaffolds.json"
assert_ok 'workflow commits only test-session permitted files' gw_commit tests
assert_ok 'workflow arms implementation ownership lock' gw session-lock.sh set implement
assert_fail 'workflow implementation lock refuses direct test edit' 1 gw session-lock.sh check new_test.go
gw_guard() { (cd "$GW_ROOT" && printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"new_test.go"}}' | bash "$GW_SCRIPTS/session-lock-guard.sh"); }
assert_fail 'workflow edit guard blocks protected tests' 2 gw_guard
printf '\n' >> "$GW_ROOT/new_test.go"
git -C "$GW_ROOT" add new_test.go
assert_fail 'workflow installed commit hook blocks staged test edit' 1 gw hooks/pre-commit
git -C "$GW_ROOT" restore --staged --worktree new_test.go
printf 'package workflow\nfunc Existing() int { return 42 }\nfunc New() int { return 0 }\n' > "$GW_ROOT/api.go"
assert_ok 'workflow captures incomplete but compilable real implementation' gw snapshot-tests.sh capture post-impl
assert_fail 'workflow refuses completion while new feature tests remain red' 1 gw snapshot-tests.sh compare post-impl
printf 'package workflow\nfunc Existing() int { return 42 }\nfunc New() int { return 9 }\n' > "$GW_ROOT/api.go"
assert_ok 'workflow real implementation captures green without overlay' gw snapshot-tests.sh capture post-impl
assert_eq 'workflow real implementation never uses retained scaffolds' 0 "$(jq '.overlay_packages|length' "$GW_ROOT/features/001-go-workflow/snapshots/post-impl.json")"
assert_ok 'workflow locked tests compare unchanged on real code' gw snapshot-tests.sh compare post-impl
assert_ok 'workflow complete implementation dirty inventory passes' gw session-lock.sh check-dirty implement
gw_finish() {
  gw snapshot-tests.sh compare post-impl && gw session-lock.sh check-dirty implement &&
  (cd "$GW_ROOT" && . "$GW_SCRIPTS/config.sh" && kaba_load_config && bash -c "$KABA_LINTER_COMMAND") &&
  gw session-lock.sh clear
}
touch "$GW_ROOT/quality-fail"
assert_fail 'workflow configured quality failure blocks completion' 1 gw_finish
assert_stdout_match 'workflow quality failure leaves implementation lock armed' 'implement' gw session-lock.sh status
rm "$GW_ROOT/quality-fail"
assert_ok 'workflow passing configured quality allows completion' gw_finish
assert_ok 'workflow commits completed disposable consumer' gw_commit implementation
assert_ok 'workflow cleanup removes exact retired row and scaffold' gw cleanup-tests.sh
assert_eq 'workflow cleanup preserves first and last table rows' 'first,last' "$(gw test-runner.sh identities --phase cleanup | jq -r '[.examples[]|select(.test_name|startswith("TestRows/"))|.test_name|split("/")[1]]|sort|join(",")')"
assert_eq 'workflow cleanup deletes recorded scaffold source' false "$([[ -e "$GW_ROOT/testdata/kaba/001-go-workflow/api.go" ]] && echo true || echo false)"
assert_eq 'workflow cleanup preserves unrelated fixture bytes' fixture "$(cat "$GW_ROOT/testdata/data.txt")"
assert_ok 'workflow cleanup repeats as a no-op' gw cleanup-tests.sh
rm -rf "$GW_ROOT"
