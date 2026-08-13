#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
NEWF="$SCRIPT_DIR/../scripts/new-feature.sh"

make_repo() {
  local dir; dir="$(mktemp -d)"
  git -C "$dir" init -q -b master
  mkdir -p "$dir/.kaba"
  cat > "$dir/.kaba/config.yml" <<'EOF'
test_dir:       spec/
test_command:   bundle exec rspec
feature_dir:    features/
linter_command: bundle exec rubocop
EOF
  git -C "$dir" add -A >/dev/null 2>&1
  git -C "$dir" -c user.email=t@t -c user.name=t commit -qm init
  for d in "$@"; do mkdir -p "$dir/features/$d"; done
  printf '%s' "$dir"
}

r1="$(make_repo)"
assert_stdout_match "first feature is 001" 'FEATURE_NUM=001' bash -c "cd '$r1' && '$NEWF' first-thing"
assert_file_exists  "creates the feature dir" "$r1/features/001-first-thing"
assert_stdout_match "checks out the new branch" '^001-first-thing$' \
  sh -c "git -C '$r1' rev-parse --abbrev-ref HEAD"

r2="$(make_repo 001-a 002-b 005-e)"
assert_stdout_match "next number is highest+1" 'FEATURE_NUM=006' bash -c "cd '$r2' && '$NEWF' sixth"
assert_stdout_match "branch name joins num and slug" 'BRANCH=006-sixth' \
  bash -c "cd '$r2' && git checkout -q master && git branch -qD 006-sixth && rm -rf features/006-sixth && '$NEWF' sixth"

r3="$(make_repo)"
assert_fail        "missing slug exits 1" 1 bash -c "cd '$r3' && '$NEWF'"
assert_stderr_match "missing slug explains usage" '[Uu]sage' bash -c "cd '$r3' && '$NEWF'"

# Numbering also respects existing NNN- branches — a migrated repo keeps its old
# numbered branches after the feature dirs are frozen elsewhere.
r4="$(make_repo)"
git -C "$r4" branch 003-already-taken
assert_stdout_match "numbering skips past NNN- branches" 'FEATURE_NUM=004' \
  bash -c "cd '$r4' && '$NEWF' after-branches"

rm -rf "$r1" "$r2" "$r3" "$r4"
