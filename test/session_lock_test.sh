#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
LOCK="$SCRIPT_DIR/../scripts/session-lock.sh"

make_repo() {
  local dir; dir="$(mktemp -d)"
  dir="$(cd "$dir" && pwd -P)"  # macOS: mktemp returns /var/… but git prints /private/var/…
  git -C "$dir" init -q -b master
  mkdir -p "$dir/.kaba"
  cat > "$dir/.kaba/config.yml" <<'EOF'
test_dir:       spec/
test_command:   bundle exec rspec
feature_dir:    features/
test_writable:  [Gemfile, Gemfile.lock, config/environments/test.rb, spec_support/]
linter_command: bundle exec rubocop
EOF
  printf '%s' "$dir"
}

repo="$(make_repo)"
lock() { (cd "$repo" && "$LOCK" "$@"); }

# --- mode off ---
assert_stdout_match "status reports off when unlocked" 'off' lock status
assert_ok           "off mode permits anything"        lock check spec/models/x_spec.rb

# --- implement mode: everything except test_dir ---
lock set implement >/dev/null
assert_stdout_match "status reports implement"          'implement' lock status
assert_fail         "implement denies test_dir"         1 lock check spec/models/x_spec.rb
assert_ok           "implement allows app/"             lock check app/models/x.rb
assert_ok           "implement allows Gemfile"          lock check Gemfile
assert_ok           "implement allows feature_dir"      lock check features/001-a/spec.md
assert_ok           "implement allows docs/"            lock check docs/readme.md
assert_stderr_match "implement violation names test dir" 'spec/' lock check spec/x_spec.rb

# The one-character trap: spec/ must not match specs/.
assert_ok "implement does not confuse specs/ with spec/" lock check specs/legacy/notes.md

# Path canonicalization: symlink forms, doubled slashes, and repeated ./ must not
# slip an absolute test_dir path past the prefix rules.
symrepo="$(mktemp -d)/link"
ln -s "$repo" "$symrepo"
assert_fail "implement denies symlink-form absolute path" 1 lock check "$symrepo/spec/models/x_spec.rb"
assert_fail "implement denies physical absolute path"     1 lock check "$repo/spec/models/x_spec.rb"
assert_fail "implement denies .// form"                   1 lock check ".//spec/x_spec.rb"
assert_fail "implement denies ././ form"                  1 lock check "././spec/x_spec.rb"
assert_fail "implement denies doubled-slash form"         1 lock check "$repo//spec/models/x_spec.rb"

# --- test mode: only test_dir, feature_dir, test_writable ---
lock set test >/dev/null
assert_ok   "test allows test_dir"            lock check spec/models/x_spec.rb
assert_ok   "test allows feature_dir"         lock check features/001-a/test-plan.md
assert_ok   "test allows exact carve-out"     lock check Gemfile
assert_ok   "test allows nested exact carve-out" lock check config/environments/test.rb
assert_ok   "test allows subtree carve-out"   lock check spec_support/helper.rb
assert_fail "test denies app/"                1 lock check app/models/x.rb
assert_fail "test denies db/"                 1 lock check db/schema.rb
assert_fail "test denies docs/"               1 lock check docs/readme.md
assert_fail "test denies config/ generally"   1 lock check config/routes.rb

# Carve-outs are visible, not hidden in YAML.
assert_stdout_match "status lists carve-outs"    'spec_support/' lock status
assert_stderr_match "violation lists carve-outs" 'spec_support/' lock check app/models/x.rb

# Traversal cannot route around the prefix rules — '..' is refused, fail closed.
assert_fail "refuses .. segments" 1 lock check app/../spec/x_spec.rb

# A config with no test_writable at all must not break status or violation output.
repo2="$(mktemp -d)"
git -C "$repo2" init -q -b master
mkdir -p "$repo2/.kaba"
cat > "$repo2/.kaba/config.yml" <<'EOF'
test_dir:       spec/
test_command:   bundle exec rspec
feature_dir:    features/
linter_command: bundle exec rubocop
EOF
lock2() { (cd "$repo2" && "$LOCK" "$@"); }
lock2 set test >/dev/null
assert_ok   "status survives empty carve-outs"      lock2 status
assert_fail "violation survives empty carve-outs" 1 lock2 check app/models/x.rb

# --- absolute paths and multiple args ---
assert_fail "absolute path is normalized" 1 lock check "$repo/app/models/x.rb"
assert_fail "any bad path in a list fails" 1 lock check spec/ok_spec.rb app/bad.rb

# --- clear ---
lock clear >/dev/null
assert_stdout_match "clear returns to off" 'off' lock status
assert_ok           "off permits again"    lock check app/models/x.rb

# --- invalid input ---
assert_fail "rejects an unknown mode" 1 lock set banana

# Explicit permissions protect colocated tests and fixtures at the public gate.
cp "$SCRIPT_DIR/fixtures/go-config.yml" "$repo/.kaba/config.yml"
mkdir -p "$repo/internal/pay" "$repo/internal/testutil"
touch "$repo/internal/pay/pay_test.go" "$repo/internal/pay/pay.go"
ln -s pay_test.go "$repo/internal/pay/alias.go"
ln -s pay.go "$repo/internal/pay/alias_test.go"
ln -s /tmp "$repo/internal/pay/outside"
lock set implement >/dev/null
assert_fail "implementation cannot write a colocated test" 1 lock check internal/pay/pay_test.go
assert_fail "implementation cannot remove a fixture" 1 lock check internal/pay/testdata/input.json
assert_fail "implementation cannot write test helpers" 1 lock check internal/testutil/helper.go
assert_ok "implementation can write colocated production" lock check internal/pay/pay.go
assert_ok "implementation can write shared manifest" lock check go.mod
assert_fail "implementation rejects symlink to test" 1 lock check internal/pay/alias.go
assert_fail "implementation rejects lexical test symlink" 1 lock check internal/pay/alias_test.go
touch "$repo/internal/pay/"$'controlled.go\n'
ln -s $'controlled.go\n' "$repo/internal/pay/control-alias.go"
assert_fail "implementation rejects controlled symlink target" 1 lock check internal/pay/control-alias.go
mkdir -p "$repo/internal/"$'controlled\n/nested'
ln -s $'controlled\n' "$repo/internal/control-directory"
assert_fail "implementation rejects controlled physical ancestor" 1 lock check internal/control-directory/nested/new.go
assert_fail "implementation rejects outside absolute path" 1 lock check /tmp/outside.go
assert_fail "implementation rejects outside symlink target" 1 lock check internal/pay/outside/new.go
assert_fail "implementation rejects newline path" 1 lock check $'internal/pay/new\n_test.go'
assert_fail "implementation rejects tab path" 1 lock check $'internal/pay/new\t.go'
assert_fail "implementation rejects newline with duplicate separators" 1 lock check $'internal//pay/pay.go\n'
assert_fail "implementation rejects repeated dot path" 1 lock check ././internal//pay/pay_test.go
assert_fail "implementation rejects symlink root alias" 1 lock check "$symrepo/internal/pay/pay_test.go"
lock set test >/dev/null
assert_fail "test session cannot write production" 1 lock check internal/pay/pay.go
assert_ok "test session can write colocated test" lock check internal/pay/pay_test.go
assert_ok "test session can create fixture with spaces" lock check 'internal/pay/testdata/input data.json'
assert_ok "test session can write shared manifest" lock check go.mod
assert_fail "test session rejects symlink to production" 1 lock check internal/pay/alias_test.go
assert_fail "test session rejects lexical production symlink" 1 lock check internal/pay/alias.go
ln -s absent "$repo/internal/pay/dangling_test.go"
assert_fail "test session rejects dangling symlink" 1 lock check internal/pay/dangling_test.go
lock clear >/dev/null
assert_ok "explicit off mode permits unsupported path" lock check $'/tmp/outside\n.go'

rm -rf "$repo" "$repo2" "$(dirname "$symrepo")"
