#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
SNAP="$SCRIPT_DIR/../scripts/snapshot-tests.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

REPO="$(mktemp -d)"
git -C "$REPO" init -q
mkdir -p "$REPO/.kaba"
cat > "$REPO/.kaba/config.yml" <<'EOF'
test_dir:       spec/
test_command:   "true"
feature_dir:    features/
linter_command: "true"
EOF

mk_feature() {
  local filter="$1"
  FD="$(mktemp -d)"
  mkdir -p "$FD/snapshots"
  cp "$FIXTURES/snap-baseline.json" "$FD/snapshots/baseline.json"
  jq "$filter" "$FIXTURES/plan-v3.json" > "$FD/test-plan.json"
}

vp() { (cd "$REPO" && FEATURE_DIR="$FD" "$SNAP" validate-plan); }

# --- validate-plan: schema v3 ---

mk_feature '.'
assert_ok "v3 plan with all four actions validates" vp
assert_file_exists "lock written on PASS" "$FD/snapshots/test-plan.lock.json"
assert_ok "lock is an exact copy of the plan" \
  bash -c "diff -q '$FD/test-plan.json' '$FD/snapshots/test-plan.lock.json'"

mk_feature '.version = 2'
assert_fail "schema v2 is rejected" 1 vp
assert_stderr_match "v2 rejection names the re-run" "plan-tests" vp

mk_feature '.entries[0].description = "A does one"
            | .entries[0].file = "./spec/a_spec.rb"'
assert_fail "PIN matching a baseline example is a plan error" 1 vp
assert_stderr_match "PIN inverse check names the conflict" "existing baseline example" vp

mk_feature '.entries[0].id = "./spec/c_spec.rb[1:1]"'
assert_fail "PIN with an id is rejected" 1 vp

mk_feature '.entries[0].file = "spec/c_spec.rb"'
assert_fail "PIN file without leading dot-slash is rejected" 1 vp

mk_feature '.entries[1].expected_landing = "pending"'
assert_fail "illegal MODIFY landing is rejected" 1 vp
assert_stderr_match "illegal landing names legal values" "failed" vp

mk_feature '.entries[3].expected_landing = "passed"'
assert_fail "TOUCH landing must be unchanged" 1 vp

mk_feature '.entries[1].description = "A does WRONG"'
assert_fail "description mismatch still rejected" 1 vp
mk_feature 'del(.entries[0]) | .entries[0].id = "./spec/zzz_spec.rb[9:9]"'
assert_fail "unknown identity still rejected" 1 vp

mk_feature '.entries[2].expected_landing = "pending" | .entries[1].expected_landing = "passed"'
assert_ok "MODIFY may land passed" vp

mk_feature '.'
jq '.version = 1' "$FD/snapshots/baseline.json" > "$FD/snapshots/baseline-v1.json"
mv "$FD/snapshots/baseline-v1.json" "$FD/snapshots/baseline.json"
assert_fail "validate-plan rejects a v1 baseline" 1 vp
assert_stderr_match "validate-plan v1 rejection names restart" "restart" vp

# --- compare post-test: v3 rule matrix ---

CD=""
mk_case() {
  CD="$(mktemp -d)"
  cp "$FIXTURES/snap-baseline.json" "$CD/before.json"
  jq "$1" "$FIXTURES/plan-v3.json" > "$CD/plan.json"
  cp "$CD/plan.json" "$CD/test-plan.lock.json"
  jq ".metadata.name = \"post-test\" | $2" "$FIXTURES/snap-baseline.json" > "$CD/after.json"
}
cmp_pt() { (cd "$REPO" && "$SNAP" compare "$CD/before.json" "$CD/after.json" post-test --test-plan "$CD/plan.json"); }
cmp_pt_json() { (cd "$REPO" && "$SNAP" --json compare "$CD/before.json" "$CD/after.json" post-test --test-plan "$CD/plan.json"); }

NEW_RED='.examples += [{"id": "./spec/c_spec.rb[1:2]", "full_description": "C new red",
  "status": "failed", "file_path": "./spec/c_spec.rb", "line_number": 9, "digest": "d-c2"}]'
NEW_PIN='.examples += [{"id": "./spec/c_spec.rb[1:1]", "full_description": "C pins existing",
  "status": "passed", "file_path": "./spec/c_spec.rb", "line_number": 4, "digest": "d-c1"}]'
PLAN_SATISFIED='(.examples[] | select(.id == "./spec/a_spec.rb[1:1]") | .status) = "failed"
  | (.examples[] | select(.id == "./spec/a_spec.rb[1:1]") | .digest) = "d-a1-modified"
  | (.examples[] | select(.id == "./spec/b_spec.rb[1:1]") | .status) = "pending"
  | (.examples[] | select(.id == "./spec/a_spec.rb[1:2]") | .digest) = "d-a2-touched"'

mk_case '.' "$PLAN_SATISFIED | $NEW_PIN | $NEW_RED"
assert_ok "full v3 plan satisfied passes" cmp_pt

mk_case '.' "$PLAN_SATISFIED | $NEW_RED
  | .examples += [{\"id\": \"./spec/c_spec.rb[1:1]\", \"full_description\": \"C pins existing\",
     \"status\": \"failed\", \"file_path\": \"./spec/c_spec.rb\", \"line_number\": 4, \"digest\": \"d-c1\"}]"
assert_fail "PIN landing failed is a violation" 1 cmp_pt
assert_stdout_match "PIN violation names the rule" "allowlisted PIN must land passed" cmp_pt

mk_case '.' "$PLAN_SATISFIED | $NEW_RED
  | .examples += [{\"id\": \"./spec/c_spec.rb[1:3]\", \"full_description\": \"C wording drifted\",
     \"status\": \"passed\", \"file_path\": \"./spec/c_spec.rb\", \"line_number\": 14, \"digest\": \"d-c3\"}]"
assert_fail "unlisted new green fails" 1 cmp_pt
assert_stdout_match "near-miss hint lists unmatched PIN" "unmatched PIN entries for this file" cmp_pt

mk_case '(.entries[1].expected_landing = "passed") | del(.entries[3])' \
  "$NEW_PIN | $NEW_RED
   | (.examples[] | select(.id == \"./spec/b_spec.rb[1:1]\") | .status) = \"pending\"
   | (.examples[] | select(.id == \"./spec/a_spec.rb[1:1]\") | .digest) = \"d-a1-modified\"
   | (.examples[] | select(.id == \"./spec/a_spec.rb[1:2]\") | .digest) = \"d-a2-x\""
assert_fail "unlisted digest drift is a violation" 1 cmp_pt
assert_stdout_match "drift violation names TOUCH" "digest drift" cmp_pt

mk_case '(.entries[1].expected_landing = "passed")' \
  "$NEW_PIN | $NEW_RED
   | (.examples[] | select(.id == \"./spec/b_spec.rb[1:1]\") | .status) = \"pending\"
   | (.examples[] | select(.id == \"./spec/a_spec.rb[1:1]\") | .digest) = \"d-a1-modified\"
   | (.examples[] | select(.id == \"./spec/a_spec.rb[1:2]\") | .digest) = \"d-a2-touched\""
assert_ok "TOUCH excuses drift; conforming MODIFY excuses its own" cmp_pt

mk_case 'del(.entries[1]) | del(.entries[1])' \
  "$NEW_PIN | $NEW_RED
   | (.examples[] | select(.id == \"./spec/a_spec.rb[1:2]\") | .status) = \"failed\""
assert_fail "TOUCH on a status flip is a violation" 1 cmp_pt
assert_stdout_match "flip violation says use MODIFY" "TOUCH cannot excuse a status change" cmp_pt
assert_stdout_match "TOUCH flip is counted as a changed violation" "Changed:.*1 violations" cmp_pt

mk_case '[.entries[0], .entries[3]] as $keep | .entries = $keep' "$NEW_RED"
assert_ok "unfulfilled PIN and unused TOUCH are warnings" cmp_pt
assert_stdout_match "warning: planned PIN did not appear" "planned PIN did not appear" cmp_pt
assert_stdout_match "warning: planned touch did not occur" "planned touch did not occur" cmp_pt

mk_case '.entries = []' \
  '(.examples[] | select(.id == "./spec/b_spec.rb[1:2]") | .digest) = null'
assert_ok "null-digest examples are drift-exempt" cmp_pt
assert_stdout_match "null-digest count printed" "without digests" cmp_pt

mk_case '.entries = []' '.'
jq '.version = 1' "$CD/before.json" > "$CD/before-v1.json"
assert_stderr_match "v1 snapshot rejected with migration note" "restart" \
  bash -c "cd '$REPO' && '$SNAP' compare '$CD/before-v1.json' '$CD/after.json' post-test --test-plan '$CD/plan.json'"

mk_case '.entries = []' \
  '.metadata.name = "post-impl"
   | (.examples[] | select(.id == "./spec/a_spec.rb[1:2]") | .digest) = "d-a2-x"'
assert_fail "post-impl digest drift fails" 1 \
  bash -c "cd '$REPO' && '$SNAP' compare '$CD/before.json' '$CD/after.json' post-impl"
mk_case '.entries = []' '.metadata.name = "post-impl"'
assert_ok "post-impl identical snapshots pass" \
  bash -c "cd '$REPO' && '$SNAP' compare '$CD/before.json' '$CD/after.json' post-impl"

# --- compare post-test: plan lock ---

mk_case '.' "$PLAN_SATISFIED | $NEW_PIN | $NEW_RED"
jq '.entries[1].expected_landing = "passed"' "$CD/plan.json" > "$CD/plan2.json" && mv "$CD/plan2.json" "$CD/plan.json"
assert_fail "edited locked entry fails the lock check" 1 cmp_pt
assert_stderr_match "lock failure names in-session edit" "plan edited in-session" cmp_pt

mk_case '.' "$PLAN_SATISFIED | $NEW_PIN | $NEW_RED"
jq 'del(.entries[3])' "$CD/plan.json" > "$CD/plan2.json" && mv "$CD/plan2.json" "$CD/plan.json"
assert_fail "deleted locked entry fails the lock check" 1 cmp_pt

mk_case '.' "$PLAN_SATISFIED | $NEW_PIN | $NEW_RED
  | (.examples[] | select(.id == \"./spec/b_spec.rb[1:2]\") | .digest) = \"drifted\""
jq '(.examples[] | select(.id == "./spec/b_spec.rb[1:2]") | .digest) = "was-here"' \
  "$CD/before.json" > "$CD/b2.json" && mv "$CD/b2.json" "$CD/before.json"
cp "$CD/plan.json" "$CD/test-plan.lock.json"
jq '.entries += [{"action": "TOUCH", "expected_landing": "unchanged",
  "id": "./spec/b_spec.rb[1:2]", "file": "./spec/b_spec.rb",
  "description": "B has no digest", "source": "fix-tests", "finding": "R1"}]' \
  "$CD/plan.json" > "$CD/plan2.json" && mv "$CD/plan2.json" "$CD/plan.json"
assert_ok "appended fix-tests TOUCH passes lock and excuses drift" cmp_pt
assert_stdout_match "appended entries printed at go/no-go" "appended in-session" cmp_pt
assert_stdout_match "appended entry names its finding" "finding R1" cmp_pt
assert_stdout_match "allowlist counts planned and appended entries" "4 entries from plan, 1 appended" cmp_pt

mk_case '.' "$PLAN_SATISFIED | $NEW_PIN | $NEW_RED"
jq '.entries += [{"action": "TOUCH", "expected_landing": "unchanged",
  "id": "./spec/b_spec.rb[1:2]", "file": "./spec/b_spec.rb", "description": "B has no digest"}]' \
  "$CD/plan.json" > "$CD/plan2.json" && mv "$CD/plan2.json" "$CD/plan.json"
assert_fail "append without fix-tests provenance fails" 1 cmp_pt
assert_stderr_match "provenance failure names the entry" "provenance" cmp_pt

mk_case '.' "$PLAN_SATISFIED | $NEW_PIN | $NEW_RED"
jq '.entries += [{"action": "REMOVE", "expected_landing": "pending",
  "id": "./spec/b_spec.rb[1:2]", "file": "./spec/b_spec.rb", "description": "B has no digest",
  "source": "fix-tests", "finding": "R2"}]' \
  "$CD/plan.json" > "$CD/plan2.json" && mv "$CD/plan2.json" "$CD/plan.json"
assert_fail "appended REMOVE is illegal" 1 cmp_pt

mk_case '.' "$PLAN_SATISFIED | $NEW_PIN | $NEW_RED"
rm "$CD/test-plan.lock.json"
assert_fail "missing lock dies" 1 cmp_pt
assert_stderr_match "missing lock names validate-plan" "validate-plan" cmp_pt

# --- allowlist-append ---

mk_append_feature() {
  mk_feature '.'
  cat > "$FD/test-plan.md" <<'EOF'
# Test Plan: fixture

## Planned State Changes

| Action | Identity (address) | Description | Expected landing | Reason |
|--------|--------------------|-------------|------------------|--------|
| MODIFY | ./spec/a_spec.rb[1:1] | A does one | failed | fixture |

## Criteria Mapping

| Criterion | File |
|-----------|------|
EOF
}
ap() { (cd "$REPO" && FEATURE_DIR="$FD" "$SNAP" allowlist-append "$@"); }

mk_append_feature
assert_ok "append TOUCH succeeds" \
  ap --action TOUCH --id "./spec/b_spec.rb[1:2]" --landing unchanged --finding R1
assert_eq "entry appended with provenance" "fix-tests" \
  "$(jq -r '.entries[-1].source' "$FD/test-plan.json")"
assert_eq "identity resolved from baseline byte-for-byte" "B has no digest" \
  "$(jq -r '.entries[-1].description' "$FD/test-plan.json")"
assert_eq "finding recorded" "R1" "$(jq -r '.entries[-1].finding' "$FD/test-plan.json")"
assert_ok "md table gained the row" grep -q "| TOUCH | ./spec/b_spec.rb\[1:2\] |" "$FD/test-plan.md"
assert_ok "md row cites the finding" grep -q "finding R1" "$FD/test-plan.md"

assert_fail "duplicate append refused" 1 \
  ap --action TOUCH --id "./spec/b_spec.rb[1:2]" --landing unchanged --finding R1

mk_append_feature
assert_fail "REMOVE refused" 1 \
  ap --action REMOVE --id "./spec/b_spec.rb[1:2]" --landing pending --finding R1
assert_stderr_match "refusal names plan-time vocabulary" "plan-tests" \
  ap --action REMOVE --id "./spec/b_spec.rb[1:2]" --landing pending --finding R1
assert_fail "PIN refused" 1 \
  ap --action PIN --id "./spec/c_spec.rb[1:1]" --landing passed --finding R1
assert_fail "unknown id refused" 1 \
  ap --action TOUCH --id "./spec/zzz_spec.rb[9:9]" --landing unchanged --finding R1
assert_fail "illegal combo refused" 1 \
  ap --action TOUCH --id "./spec/b_spec.rb[1:2]" --landing failed --finding R1
assert_fail "missing finding refused" 1 \
  ap --action TOUCH --id "./spec/b_spec.rb[1:2]" --landing unchanged --finding ""
assert_ok "append MODIFY with landing failed succeeds" \
  ap --action MODIFY --id "./spec/b_spec.rb[1:2]" --landing failed --finding R2

mk_append_feature
json_before="$(cat "$FD/test-plan.json")"
rm "$FD/test-plan.md"
assert_fail "missing markdown twin refuses append" 1 \
  ap --action TOUCH --id "./spec/b_spec.rb[1:2]" --landing unchanged --finding R5
assert_eq "missing markdown twin leaves JSON unchanged" "$json_before" "$(cat "$FD/test-plan.json")"

mk_append_feature
json_before="$(cat "$FD/test-plan.json")"
printf '%s\n' '# Test Plan without the required table' > "$FD/test-plan.md"
assert_fail "missing state-change table refuses append" 1 \
  ap --action TOUCH --id "./spec/b_spec.rb[1:2]" --landing unchanged --finding R6
assert_eq "missing state-change table leaves JSON unchanged" "$json_before" "$(cat "$FD/test-plan.json")"

mk_append_feature
jq '.version = 1' "$FD/snapshots/baseline.json" > "$FD/snapshots/baseline-v1.json"
mv "$FD/snapshots/baseline-v1.json" "$FD/snapshots/baseline.json"
assert_fail "allowlist-append rejects a v1 baseline" 1 \
  ap --action TOUCH --id "./spec/b_spec.rb[1:2]" --landing unchanged --finding R4

mk_append_feature
jq '.entries = []' "$FD/test-plan.json" > "$FD/tp.json" && mv "$FD/tp.json" "$FD/test-plan.json"
cp "$FD/test-plan.json" "$FD/snapshots/test-plan.lock.json"
assert_ok "append after lock" \
  ap --action TOUCH --id "./spec/a_spec.rb[1:2]" --landing unchanged --finding R3
AFTER="$(mktemp -d)/after.json"
jq '.metadata.name = "post-test"
    | (.examples[] | select(.id == "./spec/a_spec.rb[1:2]") | .digest) = "drifted"' \
  "$FIXTURES/snap-baseline.json" > "$AFTER"
assert_ok "script-appended entry passes lock and excuses drift" \
  bash -c "cd '$REPO' && '$SNAP' compare '$FD/snapshots/baseline.json' '$AFTER' post-test --test-plan '$FD/test-plan.json'"
