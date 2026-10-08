#!/usr/bin/env bash
# Validated scaffold generation runs only through the post-test runner hook.
# test-runner.sh owns the containing directory and EXIT/INT/TERM cleanup.
kaba_go_prepare_scaffold() {
  local feature="${FEATURE_DIR:-}" line resolved scaffold_output resolver_exit=0
  # Source-only planning and quality checks do not need virtual production code.
  # An absent feature cannot authorize a scaffold overlay for these operations.
  if [[ -z "$feature" && "${operation:-run}" != run ]]; then return 0; fi
  if [[ -z "$feature" ]]; then
    resolved="$(bash "$SCRIPT_DIR/resolve-feature.sh")" || resolver_exit=$?
    [[ "$resolver_exit" -eq 0 ]] || kaba_die 'post-test scaffolds require the current feature directory'
    while IFS= read -r line; do
      case "$line" in FEATURE_DIR=*) feature="${line#FEATURE_DIR=}" ;; esac
    done <<< "$resolved"
  fi
  [[ -n "$feature" ]] || kaba_die 'post-test scaffolds require FEATURE_DIR'
  scaffold_output="$KABA_GO_TMPDIR/scaffold"
  mkdir "$scaffold_output" || kaba_die 'could not create runner scaffold directory'
  local scaffold_args=(scaffold --root "$KABA_REPO_ROOT" --feature "$feature" --output "$scaffold_output"
    --packages "${KABA_GO_PACKAGES[*]}" --go-bin "$KABA_GO_BIN" --permission-helper "$SCRIPT_DIR/path-permissions.sh")
  [[ -z "$KABA_GO_TAGS" ]] || scaffold_args+=(--tags "$KABA_GO_TAGS")
  KABA_GO_SCAFFOLD_JSON="$(kaba_go_helper "${scaffold_args[@]}")" || kaba_die 'Go scaffold validation failed'
  KABA_GO_OVERLAY="$(printf '%s' "$KABA_GO_SCAFFOLD_JSON" | jq -r '.overlay // empty')"
}
