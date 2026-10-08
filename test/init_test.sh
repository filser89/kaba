#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
INIT="$SCRIPT_DIR/../scripts/init-project.sh"

fresh() { local d; d="$(mktemp -d)"; git -C "$d" init -q -b master; printf '%s' "$d"; }

r1="$(fresh)"
( cd "$r1" && "$INIT" --test-dir spec/ --test-command "bundle exec rspec" \
    --feature-dir features/ --linter-command "bundle exec rubocop" \
    --test-writable "Gemfile,Gemfile.lock" --rules-files "CLAUDE.md" \
    --runner-artifact "spec/examples.txt" ) >/dev/null 2>&1

assert_file_exists  "writes config.yml"        "$r1/.kaba/config.yml"
assert_file_exists  "creates feature dir"      "$r1/features"
assert_stdout_match "config has test_dir"      'test_dir'      cat "$r1/.kaba/config.yml"
assert_stdout_match "config has feature_dir"   'features/'     cat "$r1/.kaba/config.yml"
assert_stdout_match "config has test_writable" 'Gemfile.lock'  cat "$r1/.kaba/config.yml"
assert_stdout_match "points hooksPath at the shim dir" '^\.kaba/hooks$' git -C "$r1" config core.hooksPath
assert_stdout_match "sets kaba.scriptdir"      'scripts'       git -C "$r1" config kaba.scriptdir
assert_ok           "installs an executable shim" test -x "$r1/.kaba/hooks/pre-commit"
assert_stdout_match "gitignores runner artifact" 'examples.txt' cat "$r1/.gitignore"

# The written config must load cleanly through scripts/config.sh — the two must agree.
assert_ok "written config round-trips through the loader" \
  bash -c "cd '$r1' && . '$SCRIPT_DIR/../scripts/config.sh' && kaba_load_config"

# Overlap is rejected before anything is written.
r2="$(fresh)"
assert_fail "rejects overlapping dirs" 1 \
  bash -c "cd '$r2' && '$INIT' --test-dir spec/ --test-command x --feature-dir spec/features/ --linter-command y"
assert_fail "writes nothing on rejection" 1 test -f "$r2/.kaba/config.yml"

# Re-running without --force refuses — hand edits to the config are supported
# and must survive an accidental re-init.
assert_fail "re-run without --force refuses" 1 \
  bash -c "cd '$r1' && '$INIT' --test-dir spec/ --test-command x --feature-dir features/ --linter-command y"
assert_stdout_match "hand edits survive a refused re-run" 'Gemfile.lock' cat "$r1/.kaba/config.yml"

# Re-running with --force is idempotent, not duplicative.
( cd "$r1" && "$INIT" --force --test-dir spec/ --test-command "bundle exec rspec" \
    --feature-dir features/ --linter-command "bundle exec rubocop" \
    --test-writable "Gemfile,Gemfile.lock" --rules-files "CLAUDE.md" \
    --runner-artifact "spec/examples.txt" ) >/dev/null 2>&1
assert_eq "gitignore entry is not duplicated" "1" \
  "$(grep -c 'examples.txt' "$r1/.gitignore")"

# A non-empty pre-existing feature dir is refused — it may belong to another
# tool entirely (Cucumber's features/).
r3="$(fresh)"
mkdir -p "$r3/features" && touch "$r3/features/checkout.feature"
assert_fail "refuses non-empty existing feature_dir" 1 \
  bash -c "cd '$r3' && '$INIT' --test-dir spec/ --test-command x --feature-dir features/ --linter-command y"

# A core.hooksPath another tool already claims is refused, not hijacked.
r4="$(fresh)"
git -C "$r4" config core.hooksPath .husky
assert_fail "refuses a claimed core.hooksPath" 1 \
  bash -c "cd '$r4' && '$INIT' --test-dir spec/ --test-command x --feature-dir features/ --linter-command y"

rm -rf "$r1" "$r2" "$r3" "$r4"

# Explicit runner initialization writes all four independent permission lists.
r5="$(fresh)"
go_init() {
  (cd "$r5" && "$INIT" --test-runner go --test-command 'go test ./...' \
    --feature-dir features/ --linter-command 'go vet ./...' \
    --test-write-allow '**/*_test.go' --test-write-allow '**/testdata/**' \
    --test-write-allow 'features/**' --test-write-allow go.mod \
    --test-write-exclude '' --implement-write-allow '**' \
    --implement-write-exclude '**/*_test.go' --implement-write-exclude '**/testdata/**' "$@")
}
assert_ok 'initializes explicit Go permissions' go_init
assert_ok 'explicit config round-trips' bash -c "cd '$r5' && . '$SCRIPT_DIR/../scripts/config.sh' && kaba_load_config && test \"\$KABA_TEST_RUNNER\" = go && test -z \"\$KABA_TEST_DIR\""
assert_fail 'explicit config omits legacy directory' 1 grep -q '^test_dir:' "$r5/.kaba/config.yml"
assert_stdout_match 'explicit config records empty exclusions' '^test_write_exclude: \[\]$' cat "$r5/.kaba/config.yml"
assert_eq 'Go shared dependency is writable in both sessions' shared "$(cd "$r5" && bash "$SCRIPT_DIR/../scripts/path-permissions.sh" classify go.mod 2>/dev/null)"
assert_fail 'explicit reinit requires force' 1 go_init
assert_ok 'confirmed explicit overwrite supports force' go_init --force
r6="$(fresh)"
assert_fail 'partial explicit permissions fail before writes' 1 bash -c "cd '$r6' && '$INIT' --test-runner go --test-command 'go test ./...' --feature-dir features/ --linter-command true --test-write-allow '**/*_test.go'"
assert_fail 'partial explicit initialization leaves no config' 1 test -e "$r6/.kaba/config.yml"
assert_fail 'explicit permissions cannot mix legacy directory' 1 go_init --force --test-dir spec/
rm -rf "$r5" "$r6"
