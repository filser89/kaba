#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
SNAP="$SCRIPT_DIR/../scripts/snapshot-tests.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

if ! ruby -e 'require "prism"' >/dev/null 2>&1; then
  echo "  snapshot_capture tests SKIPPED (ruby with Prism unavailable)"
  return 0
fi

REPO="$(mktemp -d)"
git -C "$REPO" init -q
mkdir -p "$REPO/.kaba" "$REPO/spec"
cat > "$REPO/.kaba/config.yml" <<'EOF'
test_dir:       spec/
test_command:   ./fake-rspec
feature_dir:    features/
linter_command: "true"
EOF
cat > "$REPO/fake-rspec" <<'EOF'
#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do
  case "$1" in --out) out="$2"; shift 2 ;; *) shift ;; esac
done
cp "$FAKE_RSPEC_JSON" "$out"
exit 1
EOF
chmod +x "$REPO/fake-rspec"

cat > "$REPO/spec/a_spec.rb" <<'EOF'
# frozen_string_literal: true

RSpec.describe "A" do
  it "does one" do
    expect(1).to eq(1)
  end

  # padding so the next example starts at line 9
  it "does two" do
    expect(2).to eq(2)
  end
end
EOF

FD="$(mktemp -d)"
export FAKE_RSPEC_JSON="$FIXTURES/rspec-run.json"

cap() { (cd "$REPO" && FEATURE_DIR="$FD" "$SNAP" capture "$@"); }

assert_ok "capture succeeds against the stub runner" cap post-test
SNAPFILE="$FD/snapshots/post-test.json"
assert_file_exists "snapshot written" "$SNAPFILE"
assert_eq "snapshot is version 2" "2" "$(jq -r '.version' "$SNAPFILE")"
assert_eq "mapped examples carry sha256 digests" "2" \
  "$(jq '[.examples[] | select(.digest != null and (.digest | test("^[0-9a-f]{64}$")))] | length' "$SNAPFILE")"
assert_eq "unmapped example gets digest null" "null" \
  "$(jq -r '.examples[] | select(.id == "./spec/a_spec.rb[1:3]") | .digest' "$SNAPFILE")"
assert_eq "statuses survive the join" "failed" \
  "$(jq -r '.examples[] | select(.id == "./spec/a_spec.rb[1:1]") | .status' "$SNAPFILE")"

cat > "$REPO/spec/a_spec.rb" <<'EOF'
RSpec.describe "A" do
  it "never closes" do
EOF
assert_fail "digest pass failure aborts capture" 1 cap post-test-2
assert_stderr_match "failure names the digest pass" "digest" cap post-test-3
