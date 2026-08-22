#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
DIGEST_RB="$SCRIPT_DIR/../scripts/ruby/digest_examples.rb"

if ! ruby -e 'require "prism"' >/dev/null 2>&1; then
  echo "  digest_examples tests SKIPPED (ruby with Prism unavailable)"
  return 0
fi

TMP="$(mktemp -d)"

cat > "$TMP/base_spec.rb" <<'EOF'
# frozen_string_literal: true

RSpec.describe "A" do
  it "does one" do
    expect(1).to eq(1)
  end

  it "does two" do
    expect(2).to eq(2)
  end
end
EOF

cat > "$TMP/fmt_spec.rb" <<'EOF'
# frozen_string_literal: true

RSpec.describe "A" do
    it "does one" do  # a trailing comment
        expect(1).to eq(1)
    end

  it "does two" do
      expect(2).to  eq(2)
  end
end
EOF

cat > "$TMP/chg_spec.rb" <<'EOF'
# frozen_string_literal: true

RSpec.describe "A" do
  it "does one" do
    expect(1).to eq(999)
  end

  it "does two" do
    expect(2).to eq(2)
  end
end
EOF

cat > "$TMP/loop_spec.rb" <<'EOF'
RSpec.describe "L" do
  [1, 2, 3].each do |i|
    it "handles case" do
      expect(i).to be_a(Integer)
    end
  end
end
EOF

cat > "$TMP/broken_spec.rb" <<'EOF'
RSpec.describe "B" do
  it "never closes" do
EOF

out_base="$(ruby "$DIGEST_RB" "$TMP/base_spec.rb")"
assert_eq "base file emits 2 digest lines" "2" "$(printf '%s\n' "$out_base" | wc -l | tr -d ' ')"
assert_stdout_match "line format is file<TAB>line<TAB>sha256" \
  "^${TMP}/base_spec\.rb	[0-9]+	[0-9a-f]{64}$" ruby "$DIGEST_RB" "$TMP/base_spec.rb"

digests_of() { ruby "$DIGEST_RB" "$1" | cut -f3 | sort; }
assert_eq "formatting-only edit keeps digests" "$(digests_of "$TMP/base_spec.rb")" "$(digests_of "$TMP/fmt_spec.rb")"

base_d1="$(ruby "$DIGEST_RB" "$TMP/base_spec.rb" | head -1 | cut -f3)"
chg_d1="$(ruby "$DIGEST_RB" "$TMP/chg_spec.rb" | head -1 | cut -f3)"
if [ "$base_d1" != "$chg_d1" ]; then _pass "literal change flips the digest"
else _fail "literal change flips the digest" "digests identical"; fi
base_d2="$(ruby "$DIGEST_RB" "$TMP/base_spec.rb" | sed -n 2p | cut -f3)"
chg_d2="$(ruby "$DIGEST_RB" "$TMP/chg_spec.rb" | sed -n 2p | cut -f3)"
assert_eq "untouched example keeps its digest" "$base_d2" "$chg_d2"

assert_eq "loop group emits one digest line" "1" "$(ruby "$DIGEST_RB" "$TMP/loop_spec.rb" | wc -l | tr -d ' ')"
assert_fail "parse failure aborts" 1 ruby "$DIGEST_RB" "$TMP/broken_spec.rb"
assert_fail "no arguments aborts" 1 ruby "$DIGEST_RB"
