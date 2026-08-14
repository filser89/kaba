#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/config.sh"

JSON_OUTPUT=false

show_help() {
  cat <<'EOF'
Usage: banned-patterns.sh [options] [file ...]

Scan spec files for banned test patterns (receive, expect_any_instance_of,
respond_to). Returns exit 0 on PASS, exit 1 on FAIL.

Positional arguments:
  file ...           Specific files to scan (for targeted re-validation).
                     If none given, scans all *_spec.rb files under the
                     configured test directory (see .kaba/config.yml).

Options:
  --json             Output in JSON format
  --help, -h         Show this help message
EOF
}

require_jq() {
  command -v jq >/dev/null 2>&1 || kaba_die "jq is required for --json output. Install with: brew install jq"
}

# --- Pattern definitions ---
# Each entry: label%%grep_extended_regex%%description
# Uses %% as delimiter because regexes contain |
PATTERNS=(
  'receive%%(\.to|\.to_not|\.not_to|\.and)[[:space:]]+receive[[:space:]]*\(|have_received[[:space:]]*\(%%RSpec message expectation (mocking)'
  'expect_any_instance_of%%(expect|allow)_any_instance_of[[:space:]]*\(%%Instance-level mocking/stubbing'
  'respond_to%%(\.to|\.to_not|\.not_to)[[:space:]]+respond_to\b%%Method-existence matcher (test behavior, not interface)'
)

VIOLATIONS=()

scan_files() {
  local files=("$@")
  for file in "${files[@]}"; do
    for pattern_def in "${PATTERNS[@]}"; do
      IFS='%' read -r label _ regex _ _desc <<< "$pattern_def"
      local matches
      matches=$(grep -nE "$regex" "$file" 2>/dev/null || true)
      if [[ -n "$matches" ]]; then
        while IFS= read -r match_line; do
          local line_num text
          line_num="${match_line%%:*}"
          text="${match_line#*:}"
          VIOLATIONS+=("${file}|${line_num}|${label}|${text}")
        done <<< "$matches"
      fi
    done
  done
}

print_results_text() {
  local repo_root="$1" file_count="$2" violation_count="$3"

  echo "[banned-patterns] Scanning $file_count spec file(s)..."
  echo ""

  if [[ "$violation_count" -eq 0 ]]; then
    echo "PASS: No banned patterns found"
  else
    echo "FAIL: $violation_count violation(s) found"
    echo ""
    for v in "${VIOLATIONS[@]}"; do
      IFS='|' read -r file line label text <<< "$v"
      local rel_path="${file#"$repo_root/"}"
      echo "  ${rel_path}:${line}: ${label}"
      echo "    ${text}"
    done
  fi
}

print_results_json() {
  local repo_root="$1" file_count="$2" violation_count="$3"

  local verdict="PASS"
  [[ "$violation_count" -gt 0 ]] && verdict="FAIL"

  local violations_json="[]"
  if [[ "$violation_count" -gt 0 ]]; then
    local entries=()
    for v in "${VIOLATIONS[@]}"; do
      IFS='|' read -r file line label text <<< "$v"
      local rel_path="${file#"$repo_root/"}"
      entries+=("$(jq -n --arg f "$rel_path" --arg l "$line" --arg p "$label" --arg t "$text" \
        '{file: $f, line: ($l | tonumber), pattern: $p, text: $t}')")
    done
    violations_json=$(printf '%s\n' "${entries[@]}" | jq -s .)
  fi

  jq -n \
    --arg verdict "$verdict" \
    --argjson files_scanned "$file_count" \
    --argjson violation_count "$violation_count" \
    --argjson violations "$violations_json" \
    '{verdict: $verdict, files_scanned: $files_scanned, violation_count: $violation_count, violations: $violations}'
}

# --- Argument parsing ---

FILES=()

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) show_help; exit 0 ;;
      --json) JSON_OUTPUT=true; shift ;;
      -*) kaba_die "unknown option: $1" ;;
      *) FILES+=("$1"); shift ;;
    esac
  done
}

main() {
  parse_args "$@"
  # Deferred until after arg parsing so --help never requires a config to be
  # present — parse_args exits before we get here in that case.
  kaba_load_config

  local repo_root="$KABA_REPO_ROOT"

  if [[ ${#FILES[@]} -eq 0 ]]; then
    local spec_dir="$repo_root/${KABA_TEST_DIR%/}"
    [[ -d "$spec_dir" ]] || kaba_die "spec directory not found: $spec_dir"
    while IFS= read -r f; do
      FILES+=("$f")
    done < <(find "$spec_dir" -name '*_spec.rb' -type f | sort)
    [[ ${#FILES[@]} -gt 0 ]] || kaba_die "no spec files found in $spec_dir"
  else
    for f in "${FILES[@]}"; do
      [[ -f "$f" ]] || kaba_die "file not found: $f"
    done
  fi

  if [[ "$JSON_OUTPUT" == "true" ]]; then
    require_jq
  fi

  scan_files "${FILES[@]}"

  local file_count=${#FILES[@]}
  local violation_count=${#VIOLATIONS[@]}

  if [[ "$JSON_OUTPUT" == "true" ]]; then
    print_results_json "$repo_root" "$file_count" "$violation_count"
  else
    print_results_text "$repo_root" "$file_count" "$violation_count"
  fi

  [[ "$violation_count" -eq 0 ]] && exit 0 || exit 1
}

main "$@"
