#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
RUNNER="$SCRIPT_DIR/../scripts/test-runner.sh"
RA_REPO="$(mktemp -d)"
git -C "$RA_REPO" init -q
mkdir -p "$RA_REPO/.kaba" "$RA_REPO/spec"
cat > "$RA_REPO/.kaba/config.yml" <<'EOF'
test_dir: spec/
test_command: ./fake-rspec
feature_dir: features/
linter_command: "true"
EOF
cat > "$RA_REPO/fake-rspec" <<'EOF'
#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do
  case "$1" in --out) out="$2"; shift 2 ;; *) shift ;; esac
done
cp "$FAKE_RSPEC_JSON" "$out"
exit 1
EOF
chmod +x "$RA_REPO/fake-rspec"
export FAKE_RSPEC_JSON="$SCRIPT_DIR/fixtures/rspec-run.json"
ra_run() { (cd "$RA_REPO" && bash "$RUNNER" "$@"); }
assert_ok "RSpec discovery accepts individual failures without Ruby" ra_run identities --phase baseline
ra_out="$(ra_run identities --phase baseline 2>/dev/null || true)"
assert_eq "RSpec discovery preserves positional identity" './spec/a_spec.rb[1:1]' "$(printf '%s' "$ra_out" | jq -r '.examples[0].id' 2>/dev/null)"
ra_without_go() { (go() { return 99; }; export -f go; ra_run identities --phase baseline); }
assert_ok "RSpec discovery does not require the Go toolchain" ra_without_go
assert_fail "runner rejects unknown phases" 1 ra_run identities --phase invented
RA_BAD="$RA_REPO/bad.json"
printf '%s\n' '{"examples":[],"summary":{"errors_outside_of_examples_count":1}}' > "$RA_BAD"
FAKE_RSPEC_JSON="$RA_BAD" assert_fail "RSpec load errors invalidate discovery" 1 ra_run identities --phase baseline
FAKE_RSPEC_JSON="$RA_BAD" assert_stderr_match "RSpec load error remains actionable" 'load errors|failed to load' ra_run identities --phase baseline
printf '%s\n' '{broken' > "$RA_BAD"
FAKE_RSPEC_JSON="$RA_BAD" assert_fail "malformed RSpec formatter output is rejected" 1 ra_run identities --phase baseline
sed 's@./fake-rspec@kaba-missing-test-tool@' "$RA_REPO/.kaba/config.yml" > "$RA_REPO/.kaba/config.tmp"
mv "$RA_REPO/.kaba/config.tmp" "$RA_REPO/.kaba/config.yml"
assert_stderr_match "missing RSpec command names the dependency" 'kaba-missing-test-tool.*not found' ra_run identities --phase baseline
rm -rf "$RA_REPO"
