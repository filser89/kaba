#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/config.sh"

JSON_OUTPUT=false
RSPEC_TMPFILE=""
DIGEST_TMPFILE=""

cleanup() {
  if [[ -n "$RSPEC_TMPFILE" && -f "$RSPEC_TMPFILE" ]]; then
    rm -f "$RSPEC_TMPFILE"
  fi
  if [[ -n "$DIGEST_TMPFILE" && -f "$DIGEST_TMPFILE" ]]; then
    rm -f "$DIGEST_TMPFILE"
  fi
}
trap cleanup EXIT

show_help() {
  cat <<'EOF'
Usage: snapshot-tests.sh <mode> [options]

Modes:
  capture <name>                              Run test suite and save snapshot
  compare <mode>                              Compare snapshots against workflow rules
                                              (paths resolved from the feature directory)
  compare <before> <after> <mode>             Same, with explicit snapshot paths (override)
  identities                                  Dry-run listing of every example's identity
                                              (id, full_description, file_path) to stdout
  validate-plan                               Validate test-plan.json (schema v3) against
                                              the baseline snapshot
  allowlist-append --action TOUCH|MODIFY --id <example-id>
                   --landing unchanged|failed|passed --finding <ID>
                                              Append one human-approved allowlist entry
                                              (fix-tests escalations only; identity is
                                              resolved from the baseline snapshot)

Global options:
  --json             Output in JSON format
  --help, -h         Show this help message

Capture:
  <name>             Snapshot name (e.g. baseline, post-test, post-impl)
                     Must match [a-zA-Z0-9_-]
                     Requires ruby 3.3+ with Prism (per-example content digests)
                     "baseline" refuses to overwrite an existing baseline while the
                     test directory has in-progress work (resume mode)

Compare:
  <mode>             Comparison rules: post-test or post-impl
                     post-test resolves and REQUIRES test-plan.json (schema v3)
  --test-plan <path> Override the resolved test-plan.json path (fixtures/debugging)
EOF
}

require_jq() {
  command -v jq >/dev/null 2>&1 || kaba_die "jq is required. Install with: brew install jq"
}

# The test runner binary is whatever $KABA_TEST_COMMAND names — check its first
# word so a missing toolchain (bundler, npm, ...) fails loudly before we shell out.
require_test_command() {
  local bin="${KABA_TEST_COMMAND%% *}"
  command -v "$bin" >/dev/null 2>&1 || kaba_die "$bin not found (required to run: $KABA_TEST_COMMAND)"
}

validate_name() {
  local name="$1"
  [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || kaba_die "name must match [a-zA-Z0-9_-]: $name"
}

# Resolves FEATURE_DIR the same way in every mode: honor a pre-set environment
# FEATURE_DIR (what makes this script smoke-testable outside a feature branch),
# otherwise ask resolve-feature.sh and parse its KEY=value lines — never eval,
# since paths may contain spaces.
resolve_feature_dir() {
  [[ -n "${FEATURE_DIR:-}" ]] && return 0
  local line
  while IFS= read -r line; do
    case "$line" in
      FEATURE_DIR=*) FEATURE_DIR="${line#FEATURE_DIR=}" ;;
    esac
  done < <("$SCRIPT_DIR/resolve-feature.sh")
  [[ -n "${FEATURE_DIR:-}" ]] || kaba_die "resolve-feature.sh did not produce FEATURE_DIR"
}

# Shared RSpec invocation: runs the suite with the JSON formatter into RSPEC_TMPFILE,
# validates the JSON, and applies the load-error guard. This is the ONLY place the
# suite is invoked and the ONLY home of the guard — capture and identities are both
# thin consumers of it. Caller must have kaba_load_config'd first (KABA_REPO_ROOT,
# KABA_TEST_COMMAND).
#
# Load errors (e.g. a spec referencing a not-yet-defined constant, or a missing
# test DB) make RSpec register zero examples for the affected files. Output built
# from such a run is unreliable: a snapshot would silently pass the red/green gate
# on nothing, and an identity listing would be partial — a plan authored or
# validated against it has silent gaps. Fail loudly instead. A legitimate empty
# suite (0 examples, 0 load errors) still passes.
run_rspec_json() {
  local dry_run="$1"
  require_test_command

  RSPEC_TMPFILE=$(mktemp "${TMPDIR:-/tmp}/rspec-json.XXXXXX")

  local rspec_exit=0
  if [[ "$dry_run" == "true" ]]; then
    # Dry run feeds machine consumers (identities) — the runner's own stdout must
    # not pollute the mode's JSON output. No progress formatter, stdout discarded.
    (cd "$KABA_REPO_ROOT" && $KABA_TEST_COMMAND --dry-run --format json --out "$RSPEC_TMPFILE" >/dev/null) || rspec_exit=$?
  else
    (cd "$KABA_REPO_ROOT" && $KABA_TEST_COMMAND --format json --out "$RSPEC_TMPFILE" --format progress) || rspec_exit=$?
  fi

  if [[ ! -f "$RSPEC_TMPFILE" ]] || ! jq -e '.examples' "$RSPEC_TMPFILE" >/dev/null 2>&1; then
    kaba_die "RSpec failed to produce valid JSON"
  fi

  local errors_outside
  errors_outside=$(jq '.summary.errors_outside_of_examples_count // 0' "$RSPEC_TMPFILE")
  if [[ "$errors_outside" -gt 0 ]]; then
    echo "[snapshot] RSpec reported $errors_outside error(s) outside of examples — spec files failed to load." >&2
    echo "[snapshot] No output was produced. Re-run the suite to see the load errors:" >&2
    echo "    (cd \"$KABA_REPO_ROOT\" && $KABA_TEST_COMMAND)" >&2
    kaba_die "aborting due to load errors (errors_outside_of_examples_count=$errors_outside)"
  fi
}

# Joins a content digest onto every captured example. Hard dependency: ruby 3.3+
# with Prism — a digest gate that silently doesn't fire is worse than no gate,
# so absence or failure of the pass aborts the capture.
run_digest_pass() {
  command -v ruby >/dev/null 2>&1 \
    || kaba_die "ruby is required for snapshot digests (ruby 3.3+ with the Prism gem)"
  DIGEST_TMPFILE=$(mktemp "${TMPDIR:-/tmp}/digests.XXXXXX")
  local spec_files
  spec_files=$(jq -r '[.examples[].file_path] | unique | .[]' "$RSPEC_TMPFILE")
  if [[ -z "$spec_files" ]]; then
    : > "$DIGEST_TMPFILE"
    return 0
  fi
  if ! (cd "$KABA_REPO_ROOT" && printf '%s\n' "$spec_files" | tr '\n' '\0' \
        | xargs -0 ruby "$SCRIPT_DIR/ruby/digest_examples.rb" > "$DIGEST_TMPFILE"); then
    kaba_die "digest pass failed — ruby 3.3+ with Prism is required, and every spec file must parse (see stderr above)"
  fi
}

run_capture() {
  local name="$1"
  validate_name "$name"

  resolve_feature_dir

  local snapshot_dir="$FEATURE_DIR/snapshots"
  local snapshot_file="$snapshot_dir/${name}.json"

  # Baseline resume-guard: recapturing the baseline over half-written test work
  # would absorb the new tests into the baseline and silently exempt them from
  # the new-test gate. A dirty test directory means a session is in progress —
  # keep the existing baseline. Test directory comes from config ($KABA_TEST_DIR),
  # same as session-lock.sh.
  if [[ "$name" == "baseline" && -f "$snapshot_file" ]]; then
    if [[ -n "$(git -C "$KABA_REPO_ROOT" status --porcelain -- "$KABA_TEST_DIR" 2>/dev/null)" ]]; then
      echo "[snapshot] Resume mode: test directory has in-progress work — existing baseline preserved."
      return 0
    fi
  fi

  mkdir -p "$snapshot_dir"

  local commit
  commit=$(git -C "$KABA_REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "")

  local branch
  branch=$(git -C "$KABA_REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  local feature_name
  feature_name=$(basename "$FEATURE_DIR")

  echo "[snapshot] Running test suite..."
  run_rspec_json false
  echo "[snapshot] Computing example digests..."
  run_digest_pass

  local captured_at
  captured_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local total passed failed pending
  total=$(jq '.examples | length' "$RSPEC_TMPFILE")
  passed=$(jq '[.examples[] | select(.status == "passed")] | length' "$RSPEC_TMPFILE")
  failed=$(jq '[.examples[] | select(.status == "failed")] | length' "$RSPEC_TMPFILE")
  pending=$(jq '[.examples[] | select(.status == "pending")] | length' "$RSPEC_TMPFILE")

  jq -n \
    --argjson version 2 \
    --arg captured_at "$captured_at" \
    --arg branch "$branch" \
    --arg commit "$commit" \
    --arg feature "$feature_name" \
    --arg name "$name" \
    --argjson total "$total" \
    --argjson passed "$passed" \
    --argjson failed "$failed" \
    --argjson pending "$pending" \
    --rawfile digests "$DIGEST_TMPFILE" \
    --slurpfile rspec "$RSPEC_TMPFILE" \
    '{
      version: $version,
      metadata: {
        captured_at: $captured_at,
        branch: $branch,
        commit: $commit,
        feature: $feature,
        name: $name
      },
      examples: [
        ($digests | split("\n") | map(select(length > 0) | split("\t")
          | {key: (.[0] + ":" + .[1]), value: .[2]}) | from_entries) as $dmap |
        $rspec[0].examples[] | {
          id: .id,
          full_description: .full_description,
          status: .status,
          file_path: .file_path,
          line_number: .line_number,
          digest: ($dmap[(.file_path + ":" + (.line_number | tostring))] // null)
        }
      ],
      summary: {
        total: $total,
        passed: $passed,
        failed: $failed,
        pending: $pending
      }
    }' > "$snapshot_file"

  print_capture_summary "$name" "$snapshot_file" "$total" "$passed" "$failed" "$pending"
}

print_capture_summary() {
  local name="$1" file="$2" total="$3" passed="$4" failed="$5" pending="$6"

  if [[ "$JSON_OUTPUT" == "true" ]]; then
    jq -n \
      --arg name "$name" \
      --arg file "$file" \
      --argjson total "$total" \
      --argjson passed "$passed" \
      --argjson failed "$failed" \
      --argjson pending "$pending" \
      '{name: $name, file: $file, summary: {total: $total, passed: $passed, failed: $failed, pending: $pending}}'
  else
    echo ""
    echo "[snapshot] Captured \"$name\" → $file"
    echo ""
    echo "  Total:   $total"
    echo "  Passed:  $passed"
    echo "  Failed:  $failed"
    echo "  Pending: $pending"
    if [[ "$total" -eq 0 ]]; then
      echo ""
      echo "  WARNING: No test examples found"
    fi
  fi
}

# Dry-run identity listing: the only legal source for allowlist addresses and
# descriptions. No snapshot is written; output goes to stdout.
run_identities() {
  run_rspec_json true
  jq '[.examples[] | {id, full_description, file_path}]' "$RSPEC_TMPFILE"
}

# The single definition of allowlist identity matching, shared (textually) by
# validate-plan and compare: an entry matches an example when the ids are equal,
# or the entry id is a group address and the example sits under it — the trailing
# "]" is swapped for ":" so "[1:2]" matches "[1:2:3]" but never "[1:20:1]".
JQ_ENTRY_MATCHES='def entry_matches($e; $exid):
  ($exid == $e.id) or ($exid | startswith(($e.id | rtrimstr("]")) + ":"));'

require_snapshot_v2() {
  local snapshot_file="$1" snapshot_version
  snapshot_version=$(jq -r '.version // "missing"' "$snapshot_file" 2>/dev/null) \
    || kaba_die "invalid snapshot: $snapshot_file"
  [[ "$snapshot_version" == "2" ]] \
    || kaba_die "unsupported snapshot version in $snapshot_file: $snapshot_version (expected 2) — pre-v1.1 snapshot; finish this feature on kaba v1.0 or restart its test session"
}

read_plan_entries() {
  # Prints the entries array of a schema-v3 plan file; dies on any other version.
  local plan_file="$1"
  [[ -f "$plan_file" ]] || kaba_die "test-plan.json not found: $plan_file (run /kaba:plan-tests — the allowlist is required in post-test mode)"
  jq -e . "$plan_file" >/dev/null 2>&1 || kaba_die "test-plan.json is not valid JSON: $plan_file"
  local plan_version
  plan_version=$(jq -r '.version // "missing"' "$plan_file")
  [[ "$plan_version" == "3" ]] || kaba_die "unsupported test-plan.json version: $plan_version (expected 3) — re-run /kaba:plan-tests to regenerate"
  jq '.entries // []' "$plan_file"
}

run_validate_plan() {
  resolve_feature_dir

  local plan_file="$FEATURE_DIR/test-plan.json"
  local baseline_file="$FEATURE_DIR/snapshots/baseline.json"
  [[ -f "$baseline_file" ]] || kaba_die "baseline snapshot not found: $baseline_file (capture the baseline first)"
  require_snapshot_v2 "$baseline_file"

  local entries
  entries=$(read_plan_entries "$plan_file")

  local errors
  errors=$(jq -n \
    --argjson entries "$entries" \
    --slurpfile base "$baseline_file" \
    "$JQ_ENTRY_MATCHES"'
    $base[0].examples as $bex |
    [ $entries[] | . as $e |
      (if   $e.action == "MODIFY" then ["failed", "passed"]
       elif $e.action == "REMOVE" then ["pending"]
       elif $e.action == "PIN"    then ["passed"]
       elif $e.action == "TOUCH"  then ["unchanged"]
       else null end) as $legal |
      if $legal == null then
        {id: ($e.id // $e.file), error: "unknown action \($e.action) (expected MODIFY, REMOVE, PIN, or TOUCH)"}
      elif ($legal | index($e.expected_landing)) == null then
        {id: ($e.id // $e.file), error: "illegal expected_landing \($e.expected_landing) for \($e.action) (legal: \($legal | join(", ")))"}
      elif $e.action == "PIN" then
        (if ($e | has("id")) then
          {id: $e.file, error: "PIN entries carry no id — the example does not exist yet"}
        elif (($e.file // "") | startswith("./") | not) then
          {id: ($e.file // "missing"), error: "PIN file must use the RSpec file_path form with leading ./"}
        elif ([ $bex[] | select(.file_path == $e.file and .full_description == $e.description) ] | length) > 0 then
          {id: $e.file, error: "PIN matches an existing baseline example — pinning an existing example is a plan error (use TOUCH or MODIFY): \($e.description | tojson)"}
        else empty end)
      else
        ([ $bex[] | select(entry_matches($e; .id)) ] as $m |
         if ($m | length) == 0 then
           {id: $e.id, error: "no example in the baseline matches this identity"}
         elif ([ $m[] | select(.id == $e.id) ] | length) > 0 then
           ([ $m[] | select(.id == $e.id) ][0] as $exact |
             if $exact.full_description == $e.description then empty
             else {id: $e.id, error: "description mismatch: plan has \($e.description | tojson), baseline has \($exact.full_description | tojson)"}
             end)
         else
           ([ $m[] | select(.full_description | startswith($e.description) | not) ] as $bad |
             if ($bad | length) > 0 then
               {id: $e.id, error: "group description mismatch: \($bad | length) matched example(s) do not start with \($e.description | tojson)"}
             else empty
             end)
         end)
      end
    ]')

  local error_count entry_count
  error_count=$(echo "$errors" | jq 'length')
  entry_count=$(echo "$entries" | jq 'length')

  if [[ "$error_count" -gt 0 ]]; then
    echo "[snapshot] validate-plan: FAIL ($error_count of $entry_count entries)" >&2
    echo "$errors" | jq -r '.[] | "  [\(.id)] \(.error)"' >&2
    exit 1
  fi

  mkdir -p "$FEATURE_DIR/snapshots"
  cp "$plan_file" "$FEATURE_DIR/snapshots/test-plan.lock.json"
  echo "[snapshot] validate-plan: PASS ($entry_count entries validated against baseline; lock written to snapshots/test-plan.lock.json)"
}

# Appends one human-approved allowlist entry — the only lawful in-session write
# to test-plan.json. Identity comes byte-for-byte from the baseline and the
# provenance stamp lets compare account for the extension against the plan lock.
run_allowlist_append() {
  local action="$1" id="$2" landing="$3" finding="$4"

  case "$action" in
    TOUCH|MODIFY) ;;
    REMOVE|PIN) kaba_die "allowlist-append accepts only TOUCH or MODIFY — REMOVE and PIN are plan-time vocabulary (re-run /kaba:plan-tests)" ;;
    *) kaba_die "unknown action: $action (expected TOUCH or MODIFY)" ;;
  esac
  case "$action:$landing" in
    TOUCH:unchanged|MODIFY:failed|MODIFY:passed) ;;
    *) kaba_die "illegal expected_landing '$landing' for $action (TOUCH → unchanged; MODIFY → failed or passed)" ;;
  esac
  [[ -n "$finding" ]] || kaba_die "--finding is required (the review finding that authorized this append)"
  [[ -n "$id" ]] || kaba_die "--id is required (an exact example id from the baseline; see snapshot-tests.sh identities)"

  resolve_feature_dir
  local plan_file="$FEATURE_DIR/test-plan.json"
  local baseline_file="$FEATURE_DIR/snapshots/baseline.json"
  local md_file="$FEATURE_DIR/test-plan.md"
  [[ -f "$baseline_file" ]] || kaba_die "baseline snapshot not found: $baseline_file"
  [[ -f "$md_file" ]] || kaba_die "test-plan.md not found: $md_file (allowlist-append must update the markdown and JSON twins together)"
  require_snapshot_v2 "$baseline_file"
  local entries
  entries=$(read_plan_entries "$plan_file")

  local resolved
  resolved=$(jq --arg id "$id" '[.examples[] | select(.id == $id)] | first // empty' "$baseline_file")
  [[ -n "$resolved" ]] || kaba_die "id not found in baseline: $id (allowlist-append takes an exact example id — run snapshot-tests.sh identities)"

  local dup
  dup=$(echo "$entries" | jq --arg id "$id" --arg action "$action" \
    '[.[] | select(.id == $id and .action == $action)] | length')
  [[ "$dup" -eq 0 ]] || kaba_die "an allowlist $action entry for $id already exists"

  local entry
  entry=$(jq -n --arg action "$action" --arg landing "$landing" --arg finding "$finding" \
    --argjson ex "$resolved" \
    '{action: $action, expected_landing: $landing, id: $ex.id, file: $ex.file_path,
      description: $ex.full_description, source: "fix-tests", finding: $finding}')

  local desc row json_tmp md_tmp
  desc=$(echo "$entry" | jq -r '.description')
  row="| $action | $id | $desc | $landing | fix-tests finding $finding: human-approved escalation |"
  json_tmp=$(mktemp "$FEATURE_DIR/.test-plan-json.XXXXXX")
  md_tmp=$(mktemp "$FEATURE_DIR/.test-plan-md.XXXXXX")
  if ! jq --argjson e "$entry" '.entries += [$e]' "$plan_file" > "$json_tmp"; then
    rm -f "$json_tmp" "$md_tmp"
    kaba_die "could not append the allowlist entry to $plan_file"
  fi
  if ! append_md_row "$md_file" "$row" "$md_tmp"; then
    rm -f "$json_tmp" "$md_tmp"
    kaba_die "could not locate the Planned State Changes table in $md_file"
  fi
  mv "$json_tmp" "$plan_file"
  mv "$md_tmp" "$md_file"

  echo "[snapshot] allowlist-append: $action $id → $landing (finding $finding)"
}

append_md_row() {
  local md_file="$1" row="$2" output_file="$3"
  awk -v row="$row" '
    { lines[++n] = $0
      if ($0 ~ /^## Planned State Changes/) insec = 1
      else if (insec && $0 ~ /^## /) insec = 0
      if (insec && $0 ~ /^\|/) lastpipe = n }
    END {
      if (lastpipe == 0) exit 1
      for (i = 1; i <= n; i++) { print lines[i]; if (i == lastpipe) print row }
    }' "$md_file" > "$output_file"
}

# The live allowlist must equal the validated lock plus zero or more legal,
# provenance-stamped fix-tests appends.
verify_plan_lock() {
  local plan_entries="$1" lock_file="$2"
  [[ -f "$lock_file" ]] || kaba_die "plan lock not found: $lock_file — run snapshot-tests.sh validate-plan first (the lock is written on PASS)"
  local lock_entries report count
  lock_entries=$(jq '.entries // []' "$lock_file")
  report=$(jq -n --argjson live "$plan_entries" --argjson lock "$lock_entries" '
    ($lock | length) as $n |
    (if $live[:$n] == $lock then [] else
      [{reason: "plan edited in-session: the live allowlist does not extend the validated lock (\($n) locked entries)"}]
     end) as $prefix |
    ([ $live[$n:][] | . as $e |
       if ($e.source // "") != "fix-tests" or (($e.finding // "") | length) == 0 then
         {reason: "appended allowlist entry lacks fix-tests provenance: \($e.action) \($e.id // $e.file)"}
       elif ($e.action == "TOUCH" and $e.expected_landing == "unchanged")
         or ($e.action == "MODIFY" and ($e.expected_landing == "failed" or $e.expected_landing == "passed")) then
         empty
       else
         {reason: "appended allowlist entry is illegal: \($e.action) → \($e.expected_landing) (only TOUCH→unchanged and MODIFY→failed|passed may be appended)"}
       end ]) as $bad |
    $prefix + $bad')
  count=$(echo "$report" | jq 'length')
  if [[ "$count" -gt 0 ]]; then
    {
      echo "[snapshot] plan-lock check: FAIL"
      echo "$report" | jq -r '.[] | "  \(.reason)"'
    } >&2
    exit 1
  fi
}

run_compare() {
  local before_file="$1"
  local after_file="$2"
  local mode="$3"
  local test_plan_file="${4:-}"

  [[ "$mode" == "post-test" || "$mode" == "post-impl" ]] || kaba_die "mode must be post-test or post-impl"

  # Convention resolution: paths not given explicitly come from the feature directory.
  if [[ -z "$before_file" ]]; then
    resolve_feature_dir
    case "$mode" in
      post-test) before_file="$FEATURE_DIR/snapshots/baseline.json"; after_file="$FEATURE_DIR/snapshots/post-test.json" ;;
      post-impl) before_file="$FEATURE_DIR/snapshots/post-test.json"; after_file="$FEATURE_DIR/snapshots/post-impl.json" ;;
    esac
  fi
  if [[ "$mode" == "post-test" && -z "$test_plan_file" ]]; then
    resolve_feature_dir
    test_plan_file="$FEATURE_DIR/test-plan.json"
  fi

  [[ -f "$before_file" ]] || kaba_die "not found: $before_file"
  [[ -f "$after_file" ]] || kaba_die "not found: $after_file"

  local f
  for f in "$before_file" "$after_file"; do
    require_snapshot_v2 "$f"
  done

  # The allowlist is required in post-test mode — absence is an error, never a meaning.
  local entries="[]"
  if [[ "$mode" == "post-test" ]]; then
    entries=$(read_plan_entries "$test_plan_file")
    verify_plan_lock "$entries" "$(dirname "$before_file")/test-plan.lock.json"
  fi

  local before_name after_name
  before_name=$(jq -r '.metadata.name' "$before_file")
  after_name=$(jq -r '.metadata.name' "$after_file")

  local result
  result=$(jq -n \
    --slurpfile before "$before_file" \
    --slurpfile after "$after_file" \
    --argjson entries "$entries" \
    --arg mode "$mode" \
    "$JQ_ENTRY_MATCHES"'
    def before_map:
      reduce $before[0].examples[] as $ex ({}; . + {($ex.id): $ex});
    def after_map:
      reduce $after[0].examples[] as $ex ({}; . + {($ex.id): $ex});

    before_map as $bmap |
    after_map as $amap |

    [$amap | keys[] | select($bmap[.] == null)] as $new_ids |
    [$bmap | keys[] | select($amap[.] == null)] as $removed_ids |
    [$amap | keys[] | select($bmap[.] != null and $amap[.].status != $bmap[.].status)] as $changed_ids |
    [$amap | keys[] | select($bmap[.] != null and $amap[.].status == $bmap[.].status)] as $unchanged_ids |

    [($new_ids[] | $amap[.])] as $new_examples |
    [($removed_ids[] | $bmap[.])] as $removed_examples |
    [($changed_ids[] | {id: ., before_status: $bmap[.].status, after_status: $amap[.].status, full_description: $amap[.].full_description, file_path: $amap[.].file_path})] as $changed_examples |
    ([$unchanged_ids[] | $amap[.].status] | group_by(.) | map({(.[0]): length}) | add // {}) as $unchanged_counts |

    # Same identity and status, with two known but different structural digests.
    [$unchanged_ids[]
      | select($bmap[.].digest != null and $amap[.].digest != null and $bmap[.].digest != $amap[.].digest)
      | {id: ., status: $amap[.].status, full_description: $amap[.].full_description, file_path: $amap[.].file_path}] as $drifted |

    ([$after[0].examples[] | select(.digest == null)] | length) as $null_digests |
    [$entries[] | select((.source // "") == "fix-tests")] as $appended |

    (if $mode == "post-test" then
      [$new_examples[] | . as $nx |
        ([$entries[] | select(.action == "PIN" and .file == $nx.file_path and .description == $nx.full_description)] | length > 0) as $is_pin |
        if $is_pin then
          (if $nx.status == "passed" then empty
           else {id: $nx.id, description: $nx.full_description, reason: "allowlisted PIN must land passed, got \($nx.status)"}
           end)
        else
          (if $nx.status == "failed" then empty
           else
             ([$entries[] | select(.action == "PIN" and .file == $nx.file_path) | .description]) as $near |
             {id: $nx.id, description: $nx.full_description,
              reason: ("new test should be failed, got \($nx.status)"
                       + (if ($near | length) > 0 then "; unmatched PIN entries for this file: \($near | join(" | "))" else "" end))}
           end)
        end] +
      [$changed_examples[] | . as $ch |
        ([$entries[] | select(.action == "MODIFY") | select(entry_matches(.; $ch.id))]) as $mods |
        ([$entries[] | select(.action == "REMOVE") | select(entry_matches(.; $ch.id))]) as $rems |
        ([$entries[] | select(.action == "TOUCH")  | select(entry_matches(.; $ch.id))]) as $tchs |
        if ($mods | length) > 0 then
          (if $ch.after_status == $mods[0].expected_landing then empty
           else {id: $ch.id, description: $ch.full_description, reason: "allowlisted MODIFY must land on \($mods[0].expected_landing), got \($ch.after_status)"}
           end)
        elif ($rems | length) > 0 then
          (if $ch.after_status == "pending" then empty
           else {id: $ch.id, description: $ch.full_description, reason: "allowlisted REMOVE must land on pending, got \($ch.after_status)"}
           end)
        elif ($tchs | length) > 0 then
          {id: $ch.id, description: $ch.full_description, reason: "TOUCH cannot excuse a status change (use MODIFY): \($ch.before_status) → \($ch.after_status)"}
        elif $ch.after_status == "pending" then
          {id: $ch.id, description: $ch.full_description, reason: "transition to pending is never excused (use a REMOVE entry): \($ch.before_status) → pending"}
        else
          {id: $ch.id, description: $ch.full_description, reason: "changed from \($ch.before_status) to \($ch.after_status), not in the allowlist"}
        end] +
      [$drifted[] | . as $d |
        ([$entries[] | select(.action == "TOUCH") | select(entry_matches(.; $d.id))] | length > 0) as $is_touch |
        ([$entries[] | select(.action == "MODIFY" and .expected_landing == $d.status) | select(entry_matches(.; $d.id))] | length > 0) as $is_conforming_modify |
        if $is_touch or $is_conforming_modify then empty
        else {id: $d.id, description: $d.full_description, reason: "content changed without status change (digest drift), not allowlisted (use TOUCH)"}
        end] +
      [$entries[] | select(.action == "REMOVE") | . as $e |
        $amap | to_entries[] | .value |
        select(entry_matches($e; .id)) |
        select(.status != "pending") |
        select($bmap[.id] != null and $bmap[.id].status == .status) |
        {id: .id, description: .full_description, reason: "planned removal not executed: still \(.status)"}
      ] +
      [$removed_examples[] | {id: .id, description: .full_description, reason: "test was removed (in-session deletion is never allowed; removals are skip-marked)"}]
    elif $mode == "post-impl" then
      [$new_examples[] | {id: .id, description: .full_description, reason: "new test added during implementation"}] +
      [$changed_examples[] | select(.before_status != "failed" or .after_status != "passed") |
        (if .before_status == "passed" and .after_status == "failed" then "regression: was passing, now failing"
         else "unexpected transition: \(.before_status) → \(.after_status)"
         end) as $reason |
        {id: .id, description: .full_description, reason: $reason}] +
      [$drifted[] | {id: .id, description: .full_description, reason: "test content changed during implementation (digest drift)"}] +
      [$removed_examples[] | {id: .id, description: .full_description, reason: "test was removed"}]
    else [] end) as $violations |

    (if $mode == "post-test" then
      [$entries[] | select(.action == "MODIFY") | . as $e |
        select(([$changed_examples[] | select(entry_matches($e; .id))] | length) == 0) |
        select(([$drifted[] | select(entry_matches($e; .id))] | length) == 0) |
        {id: $e.id, description: $e.description, reason: "planned modification did not occur"}] +
      [$entries[] | select(.action == "TOUCH") | . as $e |
        select(([$drifted[] | select(entry_matches($e; .id))] | length) == 0) |
        {id: $e.id, description: $e.description, reason: "planned touch did not occur (no content drift observed)"}] +
      [$entries[] | select(.action == "PIN") | . as $e |
        select(([$new_examples[] | select(.file_path == $e.file and .full_description == $e.description)] | length) == 0) |
        {id: ($e.file), description: $e.description, reason: "planned PIN did not appear (no matching new example)"}]
    else [] end) as $warnings |

    {
      before: $before[0].metadata.name,
      after: $after[0].metadata.name,
      mode: $mode,
      verdict: (if ($violations | length) == 0 then "PASS" else "FAIL" end),
      violations: $violations,
      warnings: $warnings,
      summary: {
        new: ($new_examples | length),
        removed: ($removed_examples | length),
        changed: ($changed_examples | length),
        unchanged: ($unchanged_ids | length),
        drifted: ($drifted | length)
      },
      null_digests: $null_digests,
      appended_entries: $appended,
      allowlist: {
        planned: (($entries | length) - ($appended | length)),
        appended: ($appended | length)
      },
      new_examples: $new_examples,
      removed_examples: $removed_examples,
      changed_examples: $changed_examples,
      unchanged_counts: $unchanged_counts
    }')

  print_compare_result "$result" "$before_name" "$after_name" "$mode"

  local verdict
  verdict=$(echo "$result" | jq -r '.verdict')
  [[ "$verdict" == "PASS" ]] && return 0 || return 1
}

print_compare_result() {
  local result="$1" before_name="$2" after_name="$3" mode="$4"

  if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo "$result" | jq .
    return
  fi

  local new changed removed unchanged violation_count warning_count
  new=$(echo "$result" | jq -r '.summary.new')
  changed=$(echo "$result" | jq -r '.summary.changed')
  removed=$(echo "$result" | jq -r '.summary.removed')
  unchanged=$(echo "$result" | jq -r '.summary.unchanged')
  violation_count=$(echo "$result" | jq '.violations | length')
  warning_count=$(echo "$result" | jq '.warnings | length')

  local verdict
  verdict=$(echo "$result" | jq -r '.verdict')

  echo "[snapshot] Comparing \"$before_name\" → \"$after_name\" (mode: $mode)"
  echo ""

  # New examples line
  if [[ "$new" -gt 0 ]]; then
    if [[ "$mode" == "post-test" ]]; then
      local new_bad
      new_bad=$(echo "$result" | jq '[.violations[] | select(.reason | startswith("new test should be failed") or startswith("allowlisted PIN"))] | length')
      if [[ "$new_bad" -eq 0 ]]; then
        echo "  New:       $new (all conform ✓)"
      else
        echo "  New:       $new ($new_bad violations ✗)"
      fi
    elif [[ "$mode" == "post-impl" ]]; then
      echo "  New:       $new ✗"
    fi
  else
    echo "  New:       0 ✓"
  fi

  # Removed
  if [[ "$removed" -gt 0 ]]; then
    echo "  Removed:   $removed ✗"
  else
    echo "  Removed:   0 ✓"
  fi

  # Changed
  if [[ "$changed" -gt 0 ]]; then
    local change_violations
    change_violations=$(echo "$result" | jq '[.violations[] | select(.reason | startswith("changed") or startswith("allowlisted") or startswith("TOUCH") or startswith("transition") or startswith("regression") or startswith("unexpected"))] | length')
    if [[ "$change_violations" -eq 0 ]]; then
      echo "  Changed:   $changed ✓"
    else
      echo "  Changed:   $changed ($change_violations violations ✗)"
    fi
  else
    echo "  Changed:   0 ✓"
  fi

  # Unchanged
  local unch_passed unch_failed unch_pending
  unch_passed=$(echo "$result" | jq '.unchanged_counts.passed // 0')
  unch_failed=$(echo "$result" | jq '.unchanged_counts.failed // 0')
  unch_pending=$(echo "$result" | jq '.unchanged_counts.pending // 0')
  echo "  Unchanged: $unchanged ($unch_passed passed, $unch_failed failed, $unch_pending pending)"

  # Drift + digest accounting
  local drifted nulld
  drifted=$(echo "$result" | jq -r '.summary.drifted')
  nulld=$(echo "$result" | jq -r '.null_digests')
  if [[ "$drifted" -gt 0 ]]; then
    local drift_violations
    drift_violations=$(echo "$result" | jq '[.violations[] | select(.reason | contains("digest drift"))] | length')
    if [[ "$drift_violations" -eq 0 ]]; then
      echo "  Drifted:   $drifted ✓ (allowlisted content edits)"
    else
      echo "  Drifted:   $drifted ($drift_violations violations ✗)"
    fi
  fi
  if [[ "$nulld" -gt 0 ]]; then
    echo "  Digests:   $nulld example(s) without digests (exempt from drift rule)"
  fi

  # Allowlist accounting — the human must see every in-session extension at go/no-go.
  local appended_count
  appended_count=$(echo "$result" | jq '.allowlist.appended')
  if [[ "$mode" == "post-test" ]]; then
    local planned_count
    planned_count=$(echo "$result" | jq '.allowlist.planned')
    echo ""
    echo "  ALLOWLIST: $planned_count entries from plan, $appended_count appended in-session"
    if [[ "$appended_count" -gt 0 ]]; then
      echo "$result" | jq -r '.appended_entries[] | "    \(.action) \(.id // .file) → \(.expected_landing) (finding \(.finding // "?")) — \(.description)"'
    fi
  fi

  # Violations
  if [[ "$violation_count" -gt 0 ]]; then
    echo ""
    echo "  VIOLATIONS:"
    echo "$result" | jq -r '.violations[] | "    [\(.reason)] \(.description)"'
  fi

  # Warnings (never affect the verdict)
  if [[ "$warning_count" -gt 0 ]]; then
    echo ""
    echo "  WARNINGS:"
    echo "$result" | jq -r '.warnings[] | "    [\(.reason)] \(.id) — \(.description)"'
  fi

  echo ""
  if [[ "$verdict" == "PASS" ]]; then
    echo "  Verdict: PASS"
  else
    echo "  Verdict: FAIL ($violation_count violations)"
  fi
}

# --- Argument parsing ---

MODE=""
CAPTURE_NAME=""
COMPARE_BEFORE=""
COMPARE_AFTER=""
COMPARE_MODE=""
TEST_PLAN_FILE=""
APPEND_ACTION=""
APPEND_ID=""
APPEND_LANDING=""
APPEND_FINDING=""

parse_args() {
  if [[ $# -eq 0 ]]; then
    show_help
    exit 0
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) show_help; exit 0 ;;
      --json) JSON_OUTPUT=true; shift ;;
      capture)
        MODE="capture"
        shift
        if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
          CAPTURE_NAME="$1"; shift
        else
          kaba_die "capture requires a <name> argument"
        fi
        ;;
      compare)
        MODE="compare"
        shift
        local pos=()
        while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do pos+=("$1"); shift; done
        case ${#pos[@]} in
          1) COMPARE_MODE="${pos[0]}" ;;
          3) COMPARE_BEFORE="${pos[0]}"; COMPARE_AFTER="${pos[1]}"; COMPARE_MODE="${pos[2]}" ;;
          *) kaba_die "compare requires either <mode> or <before> <after> <mode>" ;;
        esac
        ;;
      identities)
        MODE="identities"
        shift
        ;;
      validate-plan)
        MODE="validate-plan"
        shift
        ;;
      allowlist-append)
        MODE="allowlist-append"
        shift
        ;;
      --action)
        shift; [[ $# -gt 0 ]] || kaba_die "--action requires a value"
        APPEND_ACTION="$1"; shift
        ;;
      --id)
        shift; [[ $# -gt 0 ]] || kaba_die "--id requires a value"
        APPEND_ID="$1"; shift
        ;;
      --landing)
        shift; [[ $# -gt 0 ]] || kaba_die "--landing requires a value"
        APPEND_LANDING="$1"; shift
        ;;
      --finding)
        shift; APPEND_FINDING="${1:-}"; shift || true
        ;;
      --test-plan)
        shift
        if [[ $# -gt 0 ]]; then TEST_PLAN_FILE="$1"; shift; else kaba_die "--test-plan requires a path"; fi
        ;;
      *) kaba_die "unknown argument: $1" ;;
    esac
  done

  if [[ -z "$MODE" ]]; then
    kaba_die "missing mode: capture, compare, identities, validate-plan, or allowlist-append"
  fi
}

main() {
  require_jq
  parse_args "$@"
  # Deferred until after arg parsing so --help (and no-args) never require a
  # config to be present — parse_args exits before we get here in that case.
  kaba_load_config

  case "$MODE" in
    capture)       run_capture "$CAPTURE_NAME" ;;
    compare)       run_compare "$COMPARE_BEFORE" "$COMPARE_AFTER" "$COMPARE_MODE" "$TEST_PLAN_FILE" ;;
    identities)    run_identities ;;
    validate-plan) run_validate_plan ;;
    allowlist-append) run_allowlist_append "$APPEND_ACTION" "$APPEND_ID" "$APPEND_LANDING" "$APPEND_FINDING" ;;
  esac
}

main "$@"
