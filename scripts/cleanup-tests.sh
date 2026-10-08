#!/usr/bin/env bash
# Completed-feature cleanup with real execution gates and exact rollback.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/config.sh"
kaba_load_config
. "$SCRIPT_DIR/protected-tests.sh"
command -v jq >/dev/null 2>&1 || kaba_die 'jq is required'
[[ "$("$SCRIPT_DIR/session-lock.sh" status)" == 'session-lock: off' ]] || kaba_die 'cleanup requires session lock off'
# Legacy projects need no feature resolver; optional FEATURE_DIR restricts marker attribution.
legacy_cleanup() {
  local work files path dirty=0 before after deleted expected status=0
  work="$(mktemp -d "${TMPDIR:-/tmp}/kaba-rspec-cleanup.XXXXXX")"
  files=()
  kaba_dirty_test_work || dirty=$?
  [[ "$dirty" -eq 1 ]] || kaba_die 'test-owned paths have uncommitted changes — commit or stash first'
  kaba_protected_inventory > "$work/inventory.json" || kaba_die 'protected inventory failed'
  while IFS= read -r path; do
    if grep -qF 'REMOVED by ' "$KABA_REPO_ROOT/$path"; then files+=("$KABA_REPO_ROOT/$path"); fi
  done < <(jq -r '.[].path | select(endswith(".rb"))' "$work/inventory.json")
  if [[ "${#files[@]}" -eq 0 ]]; then rm -rf "$work"; echo '[cleanup] nothing to clean — no removal markers found'; return; fi
  "$SCRIPT_DIR/test-runner.sh" run --phase cleanup > "$work/before.json" || { rm -rf "$work"; kaba_die 'fresh RSpec run incomplete'; }
  jq -e 'all(.examples[]; .status=="passed" or .status=="pending")' "$work/before.json" >/dev/null || { rm -rf "$work"; kaba_die 'fresh RSpec suite has failures'; }
  "$SCRIPT_DIR/banned-patterns.sh" >/dev/null && (cd "$KABA_REPO_ROOT" && bash -c "$KABA_LINTER_COMMAND") || { rm -rf "$work"; kaba_die 'configured quality gate failed'; }
  local helper_args=(--pending-json "$work/before.json")
  [[ -z "${FEATURE_DIR:-}" ]] || helper_args+=(--feature "$(basename "$FEATURE_DIR")")
  for path in "${files[@]}"; do
    mkdir -p "$work/backup/$(dirname "${path#"$KABA_REPO_ROOT/"}")"
    cp -p "$path" "$work/backup/${path#"$KABA_REPO_ROOT/"}"
  done
  # Install rollback before invoking a helper that can fail after its first write.
  LEGACY_WORK="$work"; LEGACY_FILES=("${files[@]}"); LEGACY_SUCCESS=false
  legacy_restore() {
    local result=$? f
    if [[ "$LEGACY_SUCCESS" != true ]]; then
      for f in "${LEGACY_FILES[@]}"; do cp -p "$LEGACY_WORK/backup/${f#"$KABA_REPO_ROOT/"}" "$f"; done
      echo '[cleanup] verification failed — exact touched bytes restored' >&2
    fi
    rm -rf "$LEGACY_WORK"
    return "$result"
  }
  trap legacy_restore EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  (cd "$KABA_REPO_ROOT" && ruby "$SCRIPT_DIR/ruby/delete_removed_examples.rb" "${helper_args[@]}" "${files[@]}") > "$work/deleted" || kaba_die 'Prism removal failed'
  deleted="$(awk -F '\t' '{s+=$1}END{print s+0}' "$work/deleted")"
  "$SCRIPT_DIR/test-runner.sh" run --phase cleanup > "$work/after.json" || kaba_die 'remaining RSpec suite incomplete'
  jq -e 'all(.examples[]; .status=="passed" or .status=="pending")' "$work/after.json" >/dev/null || kaba_die 'remaining RSpec suite has failures'
  expected=$(( $(jq '.examples|length' "$work/before.json") - deleted ))
  [[ "$(jq '.examples|length' "$work/after.json")" -eq "$expected" ]] || kaba_die 'remaining RSpec example count differs'
  "$SCRIPT_DIR/banned-patterns.sh" >/dev/null && (cd "$KABA_REPO_ROOT" && bash -c "$KABA_LINTER_COMMAND") || kaba_die 'remaining configured quality gate failed'
  LEGACY_SUCCESS=true
  echo "[cleanup] deleted $deleted example(s); suite green ($expected examples)"
}
if [[ "$KABA_TEST_RUNNER" == rspec ]]; then legacy_cleanup; exit 0; fi
if [[ -z "${FEATURE_DIR:-}" ]]; then
  while IFS= read -r line; do case "$line" in FEATURE_DIR=*) FEATURE_DIR="${line#FEATURE_DIR=}" ;; esac; done < <("$SCRIPT_DIR/resolve-feature.sh")
fi
[[ -n "${FEATURE_DIR:-}" ]] || kaba_die 'feature directory is required'
FEATURE="$(basename "$FEATURE_DIR")"
SNAPSHOTS="$FEATURE_DIR/snapshots"
for name in baseline post-test post-impl; do
  [[ -f "$SNAPSHOTS/$name.json" ]] || kaba_die "incomplete feature: missing $name snapshot"
  jq -e --arg feature "$FEATURE" --arg name "$name" '.version==2 and .metadata.feature==$feature and .metadata.name==$name and (.examples|type)=="array"' "$SNAPSHOTS/$name.json" >/dev/null || kaba_die "invalid feature-linked $name snapshot"
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kaba-cleanup.XXXXXX")"
MUTATING=false
SUCCESS=false
TOUCHED=()
restore_cleanup() {
  local status=$? path
  if [[ "$MUTATING" == true && "$SUCCESS" != true ]]; then
    for path in "${TOUCHED[@]}"; do
      mkdir -p "$(dirname "$KABA_REPO_ROOT/$path")"
      cp -p "$WORK/backup/$path" "$KABA_REPO_ROOT/$path" || status=1
    done
    if [[ -f "$WORK/manifest-before" ]]; then cp -p "$WORK/manifest-before" "$SNAPSHOTS/scaffolds.json"; else rm -f "$SNAPSHOTS/scaffolds.json"; fi
    if [[ -f "$WORK/receipt-before" ]]; then cp -p "$WORK/receipt-before" "$SNAPSHOTS/cleanup.json"; else rm -f "$SNAPSHOTS/cleanup.json"; fi
    echo '[cleanup] verification failed — exact touched bytes and manifest restored' >&2
  fi
  rm -rf "$WORK"
  return "$status"
}
trap restore_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
make_current_snapshot() {
  local result="$1" dest="$2" inventory
  inventory="$(kaba_protected_inventory)" || kaba_die 'protected inventory failed'
  jq --arg feature "$FEATURE" --argjson inventory "$inventory" '{version:2,runner:.runner,runner_schema:.schema,context:.context,groups:.groups,examples:.examples,overlay_packages:[],scaffolds:[],implementation_required:[],protected_files:$inventory,metadata:{feature:$feature,name:"post-impl"}}' "$result" > "$dest"
}
quality_gate() {
  "$SCRIPT_DIR/banned-patterns.sh" >/dev/null || kaba_die 'cleanup source quality check failed'
  (cd "$KABA_REPO_ROOT" && bash -c "$KABA_LINTER_COMMAND") || kaba_die 'configured quality command failed'
}
"$SCRIPT_DIR/test-runner.sh" run --phase cleanup > "$WORK/before.json" || kaba_die 'fresh real-code cleanup run incomplete'
jq -e 'all(.examples[]; .status=="passed" or .status=="pending")' "$WORK/before.json" >/dev/null || kaba_die 'fresh real-code suite has failures'
make_current_snapshot "$WORK/before.json" "$WORK/current.json"
# A verified receipt permits repeated cleanup even before the deletion diff is committed.
if [[ -f "$SNAPSHOTS/cleanup.json" ]]; then
  "$SCRIPT_DIR/snapshot-tests.sh" compare "$SNAPSHOTS/cleanup.json" "$WORK/current.json" post-impl >/dev/null || kaba_die 'current tests differ from successful cleanup receipt'
  quality_gate
  echo '[cleanup] nothing to clean — verified cleanup already complete'
  SUCCESS=true
  exit 0
fi
DIRTY_STATUS=0
kaba_dirty_test_work || DIRTY_STATUS=$?
[[ "$DIRTY_STATUS" -eq 1 ]] || kaba_die 'test-owned paths have uncommitted changes or unsafe ownership — commit or stash first'
if [[ ! -f "$SNAPSHOTS/scaffolds.json" ]] && [[ "$(jq '(.scaffolds // [])|length' "$SNAPSHOTS/post-test.json")" -gt 0 ]]; then
  kaba_die 'completed feature scaffold manifest is missing'
fi
if [[ -f "$SNAPSHOTS/scaffolds.json" ]]; then
  jq -e --arg feature "$FEATURE" '.version==1 and .feature==$feature' "$SNAPSHOTS/scaffolds.json" >/dev/null || kaba_die 'invalid feature scaffold manifest'
  jq '.files' "$SNAPSHOTS/scaffolds.json" > "$WORK/manifest-records.json"
  kaba_validate_scaffolds "$WORK/manifest-records.json" "$FEATURE"
  jq -en --slurpfile manifest "$SNAPSHOTS/scaffolds.json" --slurpfile snap "$SNAPSHOTS/post-test.json" '$manifest[0].files==($snap[0].scaffolds // [])' >/dev/null || kaba_die 'scaffold manifest differs from validated snapshot'
fi
KABA_CLEANUP_COMPARE=true FEATURE_DIR="$FEATURE_DIR" "$SCRIPT_DIR/snapshot-tests.sh" compare "$SNAPSHOTS/baseline.json" "$SNAPSHOTS/post-test.json" post-test --test-plan "$FEATURE_DIR/test-plan.json" >/dev/null || kaba_die 'feature post-test gates fail'
"$SCRIPT_DIR/snapshot-tests.sh" compare "$SNAPSHOTS/post-test.json" "$SNAPSHOTS/post-impl.json" post-impl >/dev/null || kaba_die 'feature post-implementation gates fail'
"$SCRIPT_DIR/snapshot-tests.sh" compare "$SNAPSHOTS/post-test.json" "$WORK/current.json" post-impl >/dev/null || kaba_die 'fresh suite fails locked-test comparison'
quality_gate
# The post-test comparison can recover the immutable manifest from snapshot records.
if [[ -f "$SNAPSHOTS/scaffolds.json" ]]; then
  jq -e --arg feature "$FEATURE" '.version==1 and .feature==$feature' "$SNAPSHOTS/scaffolds.json" >/dev/null || kaba_die 'invalid feature scaffold manifest'
  jq '.files' "$SNAPSHOTS/scaffolds.json" > "$WORK/scaffolds.json"
  kaba_validate_scaffolds "$WORK/scaffolds.json" "$FEATURE"
  cp -p "$SNAPSHOTS/scaffolds.json" "$WORK/manifest-before"
else printf '[]' > "$WORK/scaffolds.json"; fi
. "$SCRIPT_DIR/adapters/go.sh"
kaba_go_parse_command
kaba_go_helper cleanup --go-bin "$KABA_GO_BIN" --root "$KABA_REPO_ROOT" --feature "$FEATURE" --results "$WORK/before.json" --output "$WORK/plan.json" || kaba_die 'exact Go removal planning failed'

while IFS= read -r path; do TOUCHED+=("$path"); done < <(jq -r '.files[].path' "$WORK/plan.json")
while IFS= read -r path; do TOUCHED+=("$path"); done < <(jq -r '.[].path' "$WORK/scaffolds.json")
for path in "${TOUCHED[@]}"; do
  owner="$(kaba_classify_path "$path")" || kaba_die 'unsafe cleanup source path'
  [[ "$owner" == test ]] || kaba_die 'cleanup source is not test-owned'
  [[ -f "$KABA_REPO_ROOT/$path" && ! -L "$KABA_REPO_ROOT/$path" ]] || kaba_die 'cleanup source missing or symlinked'
  mkdir -p "$(dirname "$WORK/backup/$path")"
  cp -p "$KABA_REPO_ROOT/$path" "$WORK/backup/$path"
done
[[ ! -f "$SNAPSHOTS/cleanup.json" ]] || cp -p "$SNAPSHOTS/cleanup.json" "$WORK/receipt-before"
MUTATING=true
INDEX=0
while IFS= read -r path; do
  jq -j --argjson i "$INDEX" '.files[$i].content' "$WORK/plan.json" > "$KABA_REPO_ROOT/$path"
  INDEX=$((INDEX+1))
done < <(jq -r '.files[].path' "$WORK/plan.json")
while IFS= read -r path; do rm "$KABA_REPO_ROOT/$path"; done < <(jq -r '.[].path' "$WORK/scaffolds.json")
"$SCRIPT_DIR/test-runner.sh" run --phase cleanup > "$WORK/after.json" || kaba_die 'remaining real-code suite incomplete'
jq -e 'all(.examples[]; .status=="passed" or .status=="pending")' "$WORK/after.json" >/dev/null || kaba_die 'remaining real-code suite has failures'
jq -en --slurpfile before "$WORK/before.json" --slurpfile after "$WORK/after.json" --slurpfile plan "$WORK/plan.json" '
  ($before[0].examples|map(.id)|sort)-$plan[0].removed == ($after[0].examples|map(.id)|sort)' >/dev/null || kaba_die 'exact remaining identity set differs'
quality_gate
make_current_snapshot "$WORK/after.json" "$WORK/receipt.json"
rm -f "$SNAPSHOTS/scaffolds.json"
mv "$WORK/receipt.json" "$SNAPSHOTS/cleanup.json"
SUCCESS=true
echo "[cleanup] deleted $(jq '.removed|length' "$WORK/plan.json") test(s) and $(jq 'length' "$WORK/scaffolds.json") scaffold(s); real suite and exact identities verified"
echo '[cleanup] review the deletion diff and commit'
