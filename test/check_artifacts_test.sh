#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
CHECK="$SCRIPT_DIR/../scripts/check-artifacts.sh"

# Same repo shape as resolve_feature_test.sh: config, feature dir, branch checked out.
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
  for d in "$@"; do mkdir -p "$dir/features/$d"; done
  printf '%s' "$dir"
}

run() { bash -c "cd '$1' && '$CHECK' $2"; }

assert_ok "check-artifacts.sh is executable" test -x "$CHECK"
assert_ok "check-artifacts.sh sources config.sh" grep -q "config\.sh" "$CHECK"
# Must stay in the no-jq set: the guard fails open without jq, and adding a jq
# dependency here would make the gate silently unavailable on a machine without it.
assert_fail "check-artifacts.sh needs no jq" 1 grep -q "jq " "$CHECK"

# --- the mapping is the thing that used to live in prose; assert it directly ------
m="$(make_repo 010-mapping 010-mapping)"
F="$m/features/010-mapping"
mkdir -p "$F/snapshots"
touch "$F/spec.md" "$F/acceptance-criteria.md" "$F/test-plan.md" "$F/test-plan.json" \
      "$F/code-plan.md" "$F/snapshots/post-test.json" "$F/snapshots/post-impl.json"
echo x > "$F/test-plan.md"; echo x > "$F/test-plan.json"
echo x > "$F/acceptance-criteria.md"; echo x > "$F/code-plan.md"
echo x > "$F/snapshots/post-test.json"; echo x > "$F/snapshots/post-impl.json"

assert_ok "plan-tests exits 0"  bash -c "cd '$m' && '$CHECK' plan-tests"
assert_stdout_match "plan-tests maps to both plan files" \
  'EXISTING=test-plan.md test-plan.json' run "$m" plan-tests
assert_stdout_match "acceptance-criteria maps to its doc" \
  'EXISTING=acceptance-criteria.md' run "$m" acceptance-criteria
assert_stdout_match "plan-code maps to code-plan.md" 'EXISTING=code-plan.md' run "$m" plan-code
# The two that must key on completion markers, not in-progress state.
assert_stdout_match "implement-tests maps to post-test.json" \
  'EXISTING=snapshots/post-test.json' run "$m" implement-tests
assert_stdout_match "implement-code maps to post-impl.json" \
  'EXISTING=snapshots/post-impl.json' run "$m" implement-code

# --- bad input must be loud, never a quiet PRIOR_RUN=no --------------------------
assert_fail "unknown command dies"        1 bash -c "cd '$m' && '$CHECK' plan-testz"
assert_stderr_match "unknown command names the valid set" 'expected one of' \
  bash -c "cd '$m' && '$CHECK' plan-testz"
assert_fail "no argument dies"            1 bash -c "cd '$m' && '$CHECK'"
assert_fail "extra argument dies"         1 bash -c "cd '$m' && '$CHECK' plan-tests extra"
assert_fail "whitespace argument dies"    1 bash -c "cd '$m' && '$CHECK' 'plan tests'"
assert_stderr_match "whitespace argument says so" 'whitespace' \
  bash -c "cd '$m' && '$CHECK' 'plan tests'"

# --- absent / partial / empty ----------------------------------------------------
c="$(make_repo 011-clean 011-clean)"
assert_stdout_match "nothing present reports no"     'PRIOR_RUN=no'   run "$c" plan-tests
assert_stdout_match "nothing present lists none"     'EXISTING=$'     run "$c" plan-tests
assert_stdout_match "nothing present lists missing"  'MISSING=test-plan.md test-plan.json' \
  run "$c" plan-tests
assert_ok "clean feature still exits 0" bash -c "cd '$c' && '$CHECK' plan-tests"

p="$(make_repo 012-partial 012-partial)"
echo x > "$p/features/012-partial/test-plan.md"
assert_stdout_match "partial run reports yes"        'PRIOR_RUN=yes'  run "$p" plan-tests
assert_stdout_match "partial run lists what exists"  'EXISTING=test-plan.md$' run "$p" plan-tests
assert_stdout_match "partial run lists what is gone" 'MISSING=test-plan.json' run "$p" plan-tests

e="$(make_repo 013-empty 013-empty)"
touch "$e/features/013-empty/test-plan.md" "$e/features/013-empty/test-plan.json"
assert_stdout_match "0-byte artifacts still count as existing" \
  'EXISTING=test-plan.md test-plan.json' run "$e" plan-tests
assert_stdout_match "0-byte artifacts are flagged separately" \
  'EMPTY=test-plan.md test-plan.json' run "$e" plan-tests
assert_stdout_match "0-byte artifacts still gate" 'PRIOR_RUN=yes' run "$e" plan-tests

# --- unknown vs no: the silent-no-fire bug ---------------------------------------
n="$(make_repo master 001-first)"
assert_ok "non-feature branch still exits 0" bash -c "cd '$n' && '$CHECK' plan-tests"
assert_stdout_match "non-feature branch is unknown, not no" 'PRIOR_RUN=unknown' run "$n" plan-tests
assert_stdout_match "non-feature branch gives a reason" 'REASON=no-feature-branch' \
  run "$n" plan-tests

# An ambiguous feature directory is a fault. It must never read as a fresh start.
a="$(make_repo 014-dupe 014-dupe-one 014-dupe-two)"
assert_fail "ambiguous feature dir dies" 1 bash -c "cd '$a' && '$CHECK' plan-tests"
assert_fail "ambiguous feature dir never says PRIOR_RUN=no" 1 \
  bash -c "cd '$a' && '$CHECK' plan-tests 2>/dev/null | grep -q 'PRIOR_RUN=no'"

g="$(make_repo 015-ghost)"
assert_fail "missing feature dir dies" 1 bash -c "cd '$g' && '$CHECK' plan-tests"

# --- specify keys on branch resolution, not on spec.md ---------------------------
s="$(make_repo 016-interrupted 016-interrupted)"   # dir exists, spec.md never written
assert_stdout_match "specify gates on a resolved feature, not on spec.md" \
  'PRIOR_RUN=yes' run "$s" specify
assert_stdout_match "specify still reports the missing spec" 'MISSING=spec.md' run "$s" specify
assert_stdout_match "specify off a feature branch is a fresh start" \
  'PRIOR_RUN=unknown' run "$n" specify

# --- paths with spaces round-trip ------------------------------------------------
w="$(make_repo 017-spaces)"
mkdir -p "$w/features/017-spaces dir"
git -C "$w" branch -m "017-spaces dir" 2>/dev/null || true
assert_stdout_match "FEATURE_DIR with a space survives on its own line" \
  'FEATURE_DIR=.*/017-spaces dir$' \
  bash -c "cd '$w' && FEATURE_DIR='$w/features/017-spaces dir' '$CHECK' plan-tests"

# --- no config at all ------------------------------------------------------------
b="$(mktemp -d)"; git -C "$b" init -q -b 001-nope
assert_fail "missing .kaba/config.yml dies" 1 bash -c "cd '$b' && '$CHECK' plan-tests"

rm -rf "$m" "$c" "$p" "$e" "$n" "$a" "$g" "$s" "$w" "$b"
