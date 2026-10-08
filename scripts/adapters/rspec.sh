#!/usr/bin/env bash
# RSpec invocation and Prism digests. Sourced by workflow entry points.
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
