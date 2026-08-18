#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
RESOLVE="$SCRIPT_DIR/../scripts/resolve-feature.sh"

# Repo with a config, a feature dir, and a branch checked out.
make_repo() {
  local branch="$1"; shift
  local dir; dir="$(mktemp -d)"
  dir="$(cd "$dir" && pwd -P)"  # macOS: mktemp returns /var/… but git prints /private/var/…
  git -C "$dir" init -q -b "$branch"
  mkdir -p "$dir/.kaba"
  cat > "$dir/.kaba/config.yml" <<'EOF'
test_dir:       spec/
test_command:   bundle exec rspec
feature_dir:    features/
linter_command: bundle exec rubocop
EOF
  git -C "$dir" add -A >/dev/null 2>&1
  git -C "$dir" -c user.email=t@t -c user.name=t commit -qm init
  for d in "$@"; do mkdir -p "$dir/features/$d"; touch "$dir/features/$d/spec.md"; done
  printf '%s' "$dir"
}

r1="$(make_repo 005-canonical-url 005-canonical-url)"
assert_stdout_match "resolves NNN branch to its dir" 'FEATURE_DIR=.*/features/005-canonical-url$' \
  bash -c "cd '$r1' && '$RESOLVE'"
assert_stdout_match "emits REPO_ROOT" "REPO_ROOT=$r1" bash -c "cd '$r1' && '$RESOLVE'"
assert_stdout_match "emits FEATURE_SPEC" 'FEATURE_SPEC=.*/features/005-canonical-url/spec.md$' \
  bash -c "cd '$r1' && '$RESOLVE'"

r2="$(make_repo 20260813-091500-hotfix 20260813-091500-hotfix)"
assert_stdout_match "resolves timestamp branch" 'FEATURE_DIR=.*/20260813-091500-hotfix$' \
  bash -c "cd '$r2' && '$RESOLVE'"

# Exit 3 is the benign "no feature yet" case; 1 is a fault. check-artifacts.sh
# depends on being able to tell them apart without parsing stderr.
r3="$(make_repo master 001-first)"
assert_fail        "non-feature branch exits 3" 3 bash -c "cd '$r3' && '$RESOLVE'"
assert_stderr_match "non-feature branch names the branch" 'master' bash -c "cd '$r3' && '$RESOLVE'"

r4="$(make_repo 007-ghost)"
assert_fail        "no matching dir exits 1" 1 bash -c "cd '$r4' && '$RESOLVE'"
assert_stderr_match "no matching dir errors" 'no feature directory' bash -c "cd '$r4' && '$RESOLVE'"

r5="$(make_repo 008-dupe 008-dupe-one 008-dupe-two)"
assert_fail        "multiple matches exits 1" 1 bash -c "cd '$r5' && '$RESOLVE'"
assert_stderr_match "multiple matches lists them" '008-dupe-one' bash -c "cd '$r5' && '$RESOLVE'"

rm -rf "$r1" "$r2" "$r3" "$r4" "$r5"
