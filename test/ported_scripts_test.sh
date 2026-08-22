#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
S="$SCRIPT_DIR/../scripts"

# No spec-kit naming survives anywhere in the ported scripts.
for f in snapshot-tests.sh banned-patterns.sh cleanup-tests.sh; do
  # grep exits 1 on no match — "the name is absent" means expecting exit 1.
  assert_fail "$f has no 'speckit' reference"   1 grep -q "speckit"   "$S/$f"
  assert_fail "$f has no '.specify' reference"  1 grep -q "\.specify" "$S/$f"
  assert_fail "$f has no 'common.sh' source"    1 grep -q "common\.sh" "$S/$f"
done

# No project-specific hardcoding survives.
assert_fail "snapshot-tests has no hardcoded rspec" 1 grep -q "bundle exec rspec" "$S/snapshot-tests.sh"
assert_fail "cleanup-tests has no hardcoded rspec"  1 grep -q "bundle exec rspec" "$S/cleanup-tests.sh"

# Each sources the config loader.
for f in snapshot-tests.sh banned-patterns.sh cleanup-tests.sh; do
  assert_ok "$f sources config.sh" grep -q "config\.sh" "$S/$f"
done

# Each is executable and offers help without a config present.
for f in snapshot-tests.sh banned-patterns.sh cleanup-tests.sh; do
  assert_ok "$f is executable" test -x "$S/$f"
done

# Sanctioned amendment (controller-ruled plan gap fix): cleanup-tests.sh's ruby
# helper is ruby-by-necessity (prism-based RSpec-file AST editing) and ships
# alongside the bash scripts rather than being rewritten.
assert_file_exists "ruby helper is shipped" "$S/ruby/delete_removed_examples.rb"
assert_fail "ruby helper has no '.specify' reference" 1 grep -q "\.specify" "$S/ruby/delete_removed_examples.rb"
assert_ok "cleanup-tests points at the shipped helper" grep -q "ruby/delete_removed_examples\.rb" "$S/cleanup-tests.sh"

# The digest helper (allowlist schema v3) is ruby-by-necessity like its sibling.
assert_file_exists "digest helper is shipped" "$S/ruby/digest_examples.rb"
assert_fail "digest helper has no '.specify' reference" 1 grep -q "\.specify" "$S/ruby/digest_examples.rb"
