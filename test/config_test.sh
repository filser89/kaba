#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
CONFIG_SH="$SCRIPT_DIR/../scripts/config.sh"

# Builds a throwaway git repo with the given config body; prints its path.
make_repo() {
  local dir; dir="$(mktemp -d)"
  git -C "$dir" init -q
  mkdir -p "$dir/.kaba"
  cat > "$dir/.kaba/config.yml"
  printf '%s' "$dir"
}

VALID='test_dir:       spec/
test_command:   bundle exec rspec
feature_dir:    features/
test_writable:  [Gemfile, Gemfile.lock, config/environments/test.rb]
linter_command: bundle exec rubocop
rules_files:    [CLAUDE.md]
'

repo="$(printf '%s' "$VALID" | make_repo)"

# Helper: run a snippet with config.sh sourced, inside $repo.
in_repo() { (cd "$repo" && bash -c ". '$CONFIG_SH'; $1"); }

assert_stdout_match "loads test_dir"       '^spec/$'              in_repo 'kaba_load_config; printf "%s" "$KABA_TEST_DIR"'
assert_stdout_match "loads feature_dir"    '^features/$'          in_repo 'kaba_load_config; printf "%s" "$KABA_FEATURE_DIR"'
assert_stdout_match "loads test_command"   'bundle exec rspec'    in_repo 'kaba_load_config; printf "%s" "$KABA_TEST_COMMAND"'
assert_stdout_match "loads linter_command" 'bundle exec rubocop'  in_repo 'kaba_load_config; printf "%s" "$KABA_LINTER_COMMAND"'
assert_stdout_match "test_writable is a list" 'Gemfile.lock'      in_repo 'kaba_load_config; printf "%s" "$KABA_TEST_WRITABLE"'
assert_stdout_match "rules_files is a list"   'CLAUDE.md'         in_repo 'kaba_load_config; printf "%s" "$KABA_RULES_FILES"'

# Trailing slash is normalized, not assumed.
noslash="$(printf 'test_dir: spec\ntest_command: x\nfeature_dir: features\nlinter_command: y\n' | make_repo)"
assert_stdout_match "normalizes missing trailing slash" '^spec/$' \
  bash -c "cd '$noslash' && . '$CONFIG_SH' && kaba_load_config && printf '%s' \"\$KABA_TEST_DIR\""

# Missing config file dies loudly.
bare="$(mktemp -d)"; git -C "$bare" init -q
assert_stderr_match "missing config dies" 'config.yml' \
  bash -c "cd '$bare' && . '$CONFIG_SH' && kaba_load_config"

# Missing required key dies loudly and names the key.
nokey="$(printf 'test_command: x\nfeature_dir: features/\n' | make_repo)"
assert_stderr_match "missing test_dir names the key" 'test_dir' \
  bash -c "cd '$nokey' && . '$CONFIG_SH' && kaba_load_config"

# Overlapping test_dir / feature_dir is rejected in both directions.
overlap1="$(printf 'test_dir: spec/\ntest_command: x\nfeature_dir: spec/features/\nlinter_command: y\n' | make_repo)"
assert_stderr_match "rejects feature_dir under test_dir" 'prefix' \
  bash -c "cd '$overlap1' && . '$CONFIG_SH' && kaba_load_config"

overlap2="$(printf 'test_dir: features/spec/\ntest_command: x\nfeature_dir: features/\nlinter_command: y\n' | make_repo)"
assert_stderr_match "rejects test_dir under feature_dir" 'prefix' \
  bash -c "cd '$overlap2' && . '$CONFIG_SH' && kaba_load_config"

# Inline comments are stripped, not swallowed into values.
commented="$(printf 'test_dir: spec/  # our tests\ntest_command: x\nfeature_dir: features/\nlinter_command: y\ntest_writable: [Gemfile, Gemfile.lock]  # keep in sync\n' | make_repo)"
assert_stdout_match "strips comment from scalar" '^spec/$' \
  bash -c "cd '$commented' && . '$CONFIG_SH' && kaba_load_config && printf '%s' \"\$KABA_TEST_DIR\""
assert_stdout_match "strips comment after inline list" '^Gemfile\.lock$' \
  bash -c "cd '$commented' && . '$CONFIG_SH' && kaba_load_config && printf '%s' \"\$KABA_TEST_WRITABLE\" | tail -1"

# Directory values must be plain repo-relative paths — anything else defeats the
# anchored prefix matching downstream, in the permissive direction.
dotslash="$(printf 'test_dir: ./spec/\ntest_command: x\nfeature_dir: features/\nlinter_command: y\n' | make_repo)"
assert_stderr_match "rejects ./ prefix"     'repo-relative' bash -c "cd '$dotslash' && . '$CONFIG_SH' && kaba_load_config"
absdir="$(printf 'test_dir: /tmp/spec/\ntest_command: x\nfeature_dir: features/\nlinter_command: y\n' | make_repo)"
assert_stderr_match "rejects absolute path" 'repo-relative' bash -c "cd '$absdir' && . '$CONFIG_SH' && kaba_load_config"
dotdot="$(printf 'test_dir: spec/../app/\ntest_command: x\nfeature_dir: features/\nlinter_command: y\n' | make_repo)"
assert_stderr_match "rejects .. segments"   'repo-relative' bash -c "cd '$dotdot' && . '$CONFIG_SH' && kaba_load_config"

# Not a git repo at all.
assert_stderr_match "dies outside a git repo" 'git' \
  bash -c "cd /tmp && . '$CONFIG_SH' && kaba_repo_root"

rm -rf "$repo" "$noslash" "$bare" "$nokey" "$overlap1" "$overlap2" \
       "$commented" "$dotslash" "$absdir" "$dotdot"
