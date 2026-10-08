#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
GSA_SNAP="$SCRIPT_DIR/../scripts/snapshot-tests.sh"
GSA_REPO="$(mktemp -d)"
git -C "$GSA_REPO" init -q
mkdir -p "$GSA_REPO/.kaba" "$GSA_REPO/features/one/snapshots"
cat > "$GSA_REPO/.kaba/config.yml" <<'EOF'
test_runner: go
test_command: go test ./...
feature_dir: features/
linter_command: "true"
test_write_allow: ["**/*_test.go"]
test_write_exclude: []
implement_write_allow: ["**"]
implement_write_exclude: ["**/*_test.go"]
EOF
cat > "$GSA_REPO/features/one/snapshots/baseline.json" <<'EOF'
{"version":2,"runner":"go","runner_schema":1,"context":{"count":1,"packages":"./..."},"metadata":{"name":"baseline"},"examples":[{"id":"example::TestRows/one","full_description":"TestRows/one","file_path":"rows_test.go","status":"passed","digest":"a"},{"id":"example::TestRowsExtra/one","full_description":"TestRowsExtra/one","file_path":"rows_test.go","status":"passed","digest":"b"}]}
EOF
cat > "$GSA_REPO/features/one/test-plan.json" <<'EOF'
{"version":3,"entries":[{"action":"REMOVE","id":"example::TestRows","description":"TestRows","expected_landing":"pending"},{"action":"PIN","file":"pin_test.go","description":"TestPin","expected_landing":"passed"}]}
EOF
gsa_run() { (cd "$GSA_REPO" && FEATURE_DIR="$GSA_REPO/features/one" bash "$GSA_SNAP" "$@"); }
assert_ok "Go PIN accepts native relative test paths" gsa_run validate-plan
jq '.metadata.name="post-test" | .examples[0].status="pending" | .examples += [{id:"example::TestPin",full_description:"TestPin",file_path:"pin_test.go",status:"passed",digest:"c"}] | .overlay_packages=[]' "$GSA_REPO/features/one/snapshots/baseline.json" > "$GSA_REPO/features/one/snapshots/post-test.json"
assert_ok "Go group identity matches children and excludes prefix neighbor" gsa_run compare post-test
jq '.overlay_packages=["other"]' "$GSA_REPO/features/one/snapshots/post-test.json" > "$GSA_REPO/features/one/snapshots/new.json"
mv "$GSA_REPO/features/one/snapshots/new.json" "$GSA_REPO/features/one/snapshots/post-test.json"
assert_fail "overlay-assisted PIN is rejected even across package dependencies" 1 gsa_run compare post-test
assert_stdout_match "overlay PIN error explains missing real-code proof" 'PIN.*overlay|PIN.*scaffold' gsa_run compare post-test
jq '.context.packages="./selected"' "$GSA_REPO/features/one/snapshots/post-test.json" > "$GSA_REPO/features/one/snapshots/new.json"
mv "$GSA_REPO/features/one/snapshots/new.json" "$GSA_REPO/features/one/snapshots/post-test.json"
assert_stderr_match "Go context mismatch blocks snapshot comparison" 'context mismatch' gsa_run compare post-test
jq '.runner="rspec"' "$GSA_REPO/features/one/snapshots/post-test.json" > "$GSA_REPO/features/one/snapshots/new.json"
mv "$GSA_REPO/features/one/snapshots/new.json" "$GSA_REPO/features/one/snapshots/post-test.json"
assert_stderr_match "mixed runner snapshots cannot compare" 'runner mismatch' gsa_run compare post-test
rm -rf "$GSA_REPO"
