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

# Explicit runners and quoted permissions require no legacy test directory.
go_config="$(cat "$SCRIPT_DIR/fixtures/go-config.yml")"
repo="$(printf '%s\n' "$go_config" | make_repo)"
assert_stdout_match "explicit runner is go" '^go$' in_repo 'kaba_load_config; printf "%s" "$KABA_TEST_RUNNER"'
assert_stdout_match "quoted permission has no YAML quotes" '^\*\*/\*_test.go$' in_repo 'kaba_load_config; printf "%s\n" "$KABA_TEST_WRITE_ALLOW"'
assert_stdout_match "explicit empty exclusions load" '^empty$' in_repo 'kaba_load_config; [ -z "$KABA_TEST_WRITE_EXCLUDE" ] && printf empty'
assert_stdout_match "inline permission quote stripped" '^\*\*$' in_repo 'kaba_load_config; printf "%s" "$KABA_IMPLEMENT_WRITE_ALLOW"'
rm -rf "$repo"
repo="$(printf '%s\n' "$go_config" | sed "s/implement_write_allow:.*/implement_write_allow: ['**', 'literal,comma'] # comment/" | make_repo)"
assert_stdout_match "quoted inline comma remains literal" '^literal,comma$' in_repo 'kaba_load_config; printf "%s\n" "$KABA_IMPLEMENT_WRITE_ALLOW"'
rm -rf "$repo"
for key in test_runner test_write_allow implement_write_allow test_write_exclude implement_write_exclude; do
  repo="$(printf '%s\n' "$go_config" | sed "/^$key:/,/^[^[:space:]]/{ /^$key:/d; /^[[:space:]]/d; }" | make_repo)"
  assert_stderr_match "missing explicit $key rejected" "$key" in_repo 'kaba_load_config'
  rm -rf "$repo"
done
for pattern in '!internal/**' 'internal/?' 'internal/[ab]' '../escape' '/outside' 'internal/**x'; do
  repo="$(printf '%s\n' "$go_config" | sed "s|implement_write_allow:.*|implement_write_allow: ['$pattern']|" | make_repo)"
  assert_stderr_match "invalid pattern $pattern rejected" 'pattern|repo-relative' in_repo 'kaba_load_config'
  rm -rf "$repo"
done
repo="$(printf '%s\ntest_dir: spec/\n' "$go_config" | make_repo)"
assert_stderr_match "mixed legacy directory rejected" 'mix|legacy' in_repo 'kaba_load_config'
rm -rf "$repo"
repo="$(printf '%s\ntest_writable: []\n' "$go_config" | make_repo)"
assert_stderr_match "mixed legacy carve-outs rejected" 'mix|legacy' in_repo 'kaba_load_config'
rm -rf "$repo"
repo="$(printf '%s' "$VALID" | make_repo)"
assert_stdout_match "legacy runner defaults to rspec" '^rspec$' in_repo 'kaba_load_config; printf "%s" "$KABA_TEST_RUNNER"'
rm -rf "$repo"
# Fail closed on malformed list syntax, unsupported escapes and unknown runners.
for list in "[]" "['internal\\helpers/**']" "['a',]" "['unterminated]" "['**'] garbage" "'{a: b}'" "[foo: bar]"; do
  repo="$(printf '%s\n' "$go_config" | sed '/^implement_write_allow:/d' | make_repo)"
  printf 'implement_write_allow: %s\n' "$list" >> "$repo/.kaba/config.yml"
  assert_fail "rejects invalid allow list $list" 1 in_repo 'kaba_load_config'
  rm -rf "$repo"
done
repo="$(printf '%s\n' "$go_config" | sed 's/test_runner: go/test_runner: unknown/' | make_repo)"
assert_stderr_match "unsupported runner diagnostic" 'unsupported test_runner' in_repo 'kaba_load_config'
rm -rf "$repo"
repo="$(printf '%s\n' "$go_config" | sed "s|implement_write_allow:.*|implement_write_allow: ['././internal//pay/']|" | make_repo)"
assert_stdout_match "normalizes explicit pattern separators" '^internal/pay/$' in_repo 'kaba_load_config; printf "%s" "$KABA_IMPLEMENT_WRITE_ALLOW"'
rm -rf "$repo"
repo="$(printf '%s\n' "$go_config" | sed "s|implement_write_allow:.*|implement_write_allow: ['file # label', 'it''s.go'] # comment|" | make_repo)"
assert_stdout_match "quoted hash preserved in pattern" '^file # label$' in_repo 'kaba_load_config; printf "%s\n" "$KABA_IMPLEMENT_WRITE_ALLOW"'
assert_stdout_match "single quote YAML escape decoded" "^it's.go$" in_repo 'kaba_load_config; printf "%s\n" "$KABA_IMPLEMENT_WRITE_ALLOW"'
rm -rf "$repo"

# Indentless YAML sequences must preserve exclusions rather than granting access.
repo="$(printf '%s\n' "$go_config" | sed '/^rules_files:/d; /^implement_write_exclude:/,$d' | make_repo)"
cat >> "$repo/.kaba/config.yml" <<'CFG'
implement_write_exclude:
- 'internal/*_test.go'
- 'internal/testutil/**'
rules_files: [AGENTS.md]
CFG
assert_stdout_match "indentless exclusions retain first entry" '^internal/\*_test.go$' in_repo 'kaba_load_config; printf "%s\n" "$KABA_IMPLEMENT_WRITE_EXCLUDE"'
assert_stdout_match "indentless sequence ends at next key" '^AGENTS.md$' in_repo 'kaba_load_config; printf "%s\n" "$KABA_RULES_FILES"'
assert_stdout_match "indentless exclusion protects test ownership" '^test$' in_repo '. "'"$SCRIPT_DIR"'/../scripts/path-permissions.sh"; kaba_load_config; kaba_classify_path internal/pay_test.go'
rm -rf "$repo"

# Anchors, aliases and tags are outside the flat YAML subset, including exclusions.
for entry in '&tests internal/*_test.go' '*tests' '!tag internal/*_test.go'; do
  for style in block inline; do
    repo="$(printf '%s\n' "$go_config" | sed '/^implement_write_exclude:/,$d' | make_repo)"
    if [ "$style" = block ]; then
      printf 'implement_write_exclude:\n  - %s\n' "$entry" >> "$repo/.kaba/config.yml"
    else
      printf 'implement_write_exclude: [%s]\n' "$entry" >> "$repo/.kaba/config.yml"
    fi
    assert_fail "rejects $style YAML directive $entry" 1 in_repo 'kaba_load_config'
    assert_stderr_match "diagnoses $style unsupported YAML directive" 'unsupported YAML' in_repo 'kaba_load_config'
    rm -rf "$repo"
  done
done
repo="$(printf '%s\n' "$go_config" | sed '/^implement_write_exclude:/,$d' | make_repo)"
cat >> "$repo/.kaba/config.yml" <<'CFG'
implement_write_exclude: ['&literal', '*literal']
CFG
assert_stdout_match "quoted anchor-like pattern remains literal" '^&literal$' in_repo 'kaba_load_config; printf "%s\n" "$KABA_IMPLEMENT_WRITE_EXCLUDE"'
assert_stdout_match "quoted alias-like pattern remains a glob" '^\*literal$' in_repo 'kaba_load_config; printf "%s\n" "$KABA_IMPLEMENT_WRITE_EXCLUDE"'
rm -rf "$repo"
