#!/usr/bin/env bash
# Completion follows validated feature targets, preserving unrelated baseline failures.
set -uo pipefail
SCRIPT_DIR="$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
COMP_SCRIPT="$SCRIPT_DIR/../scripts/snapshot-tests.sh"
COMP_ROOT="$(mktemp -d)"
git -C "$COMP_ROOT" init -q
mkdir -p "$COMP_ROOT/.kaba" "$COMP_ROOT/features/one/snapshots"
cp "$SCRIPT_DIR/fixtures/go-config.yml" "$COMP_ROOT/.kaba/config.yml"
COMP_SNAP="$COMP_ROOT/features/one/snapshots"
cat > "$COMP_SNAP/baseline.json" <<'JSON'
{"version":2,"runner":"go","runner_schema":1,"context":{},"metadata":{"name":"baseline","feature":"one"},"protected_files":[],"examples":[{"id":"example::TestOldRed","full_description":"TestOldRed","file_path":"api_test.go","status":"failed","digest":"old"},{"id":"example::TestModified","full_description":"TestModified","file_path":"api_test.go","status":"passed","digest":"original"}]}
JSON
cat > "$COMP_ROOT/features/one/test-plan.json" <<'JSON'
{"version":3,"entries":[{"action":"MODIFY","id":"example::TestModified","description":"TestModified","expected_landing":"failed"}]}
JSON
comp() { (cd "$COMP_ROOT" && FEATURE_DIR="$COMP_ROOT/features/one" bash "$COMP_SCRIPT" "$@"); }
assert_ok 'completion fixture validates planned MODIFY' comp validate-plan
jq '.metadata.name="post-test" | .examples[1].status="failed" | .examples[1].digest="modified" | .examples += [{id:"example::TestNew",full_description:"TestNew",file_path:"api_test.go",status:"failed",digest:"new"}]' "$COMP_SNAP/baseline.json" > "$COMP_SNAP/post-test.json"
assert_ok 'validated post-test records feature completion requirements' comp compare post-test
jq '.metadata.name="post-impl" | .examples[2].status="passed"' "$COMP_SNAP/post-test.json" > "$COMP_SNAP/post-impl.json"
assert_fail 'MODIFY case remaining failed blocks completion' 1 comp compare post-impl
jq '.metadata.name="post-impl" | .examples[1].status="passed"' "$COMP_SNAP/post-test.json" > "$COMP_SNAP/post-impl.json"
assert_fail 'new case remaining failed blocks completion' 1 comp compare post-impl
jq '.metadata.name="post-impl" | .examples[1].status="passed" | .examples[2].status="passed"' "$COMP_SNAP/post-test.json" > "$COMP_SNAP/post-impl.json"
assert_ok 'green feature tests preserve unrelated baseline failure' comp compare post-impl
jq '.examples[0].status="passed"' "$COMP_SNAP/post-impl.json" > "$COMP_ROOT/after.json"
assert_fail 'unplanned fix to unrelated baseline failure is rejected' 1 comp compare "$COMP_SNAP/post-test.json" "$COMP_ROOT/after.json" post-impl
jq 'del(.implementation_required)' "$COMP_SNAP/post-test.json" > "$COMP_ROOT/before.json"
assert_fail 'unvalidated red snapshot cannot bypass completion targets' 1 comp compare "$COMP_ROOT/before.json" "$COMP_SNAP/post-impl.json" post-impl
jq 'del(.implementation_required) | .examples |= map(.status="pending")' "$COMP_SNAP/post-test.json" > "$COMP_ROOT/before.json"
jq '.metadata.name="post-impl"' "$COMP_ROOT/before.json" > "$COMP_ROOT/after.json"
assert_fail 'unvalidated pending snapshot cannot bypass completion targets' 1 comp compare "$COMP_ROOT/before.json" "$COMP_ROOT/after.json" post-impl
rm -rf "$COMP_ROOT"
