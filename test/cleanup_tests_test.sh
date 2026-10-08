#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
if ! ruby -e 'require "rspec/core"; require "prism"' >/dev/null 2>&1; then
  echo '  cleanup legacy tests SKIPPED (RSpec/Prism unavailable)'
  return 0
fi
LC_SCRIPT="$SCRIPT_DIR/../scripts/cleanup-tests.sh"
LC_HELPER="$SCRIPT_DIR/../scripts/ruby/delete_removed_examples.rb"
lc_fixture() {
  LC_ROOT="$(mktemp -d)"
  git -C "$LC_ROOT" init -q
  mkdir -p "$LC_ROOT/.kaba" "$LC_ROOT/spec"
  cat > "$LC_ROOT/.kaba/config.yml" <<'CFG'
test_dir: spec/
test_command: rspec
feature_dir: features/
linter_command: "true"
CFG
  cat > "$LC_ROOT/spec/a_spec.rb" <<'RB'
RSpec.describe "Cleanup" do
  it "gone", skip: "REMOVED by one" do
    expect(1).to eq(0)
  end
  it "keep" do
    expect(1).to eq(1)
  end
end
RB
  printf unrelated > "$LC_ROOT/unrelated.txt"
  git -C "$LC_ROOT" add .
  git -C "$LC_ROOT" -c user.name=Test -c user.email=test@example.test commit -qm fixture
}
lc_run() { (cd "$LC_ROOT" && bash "$LC_SCRIPT"); }
lc_fixture
assert_ok 'legacy cleanup works without feature resolver prerequisites' lc_run
assert_eq 'legacy cleanup preserves neighboring example' 1 "$(rg -c 'it "keep"' "$LC_ROOT/spec/a_spec.rb")"
assert_eq 'legacy cleanup preserves unrelated bytes' unrelated "$(cat "$LC_ROOT/unrelated.txt")"
rm -rf "$LC_ROOT"
lc_fixture
LC_HASH="$(git hash-object "$LC_ROOT/spec/a_spec.rb")"
mkdir "$LC_ROOT/shim"
LC_RUBY="$(ruby -rrbconfig -e 'print RbConfig.ruby')"
cat > "$LC_ROOT/shim/ruby" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == */delete_removed_examples.rb ]]; then
  "$LC_REAL_RUBY" "$@" || exit $?
  exit 1
fi
exec "$LC_REAL_RUBY" "$@"
SH
chmod +x "$LC_ROOT/shim/ruby"
lc_partial() { (export LC_REAL_RUBY="$LC_RUBY"; export PATH="$LC_ROOT/shim:$PATH"; lc_run); }
assert_fail 'legacy partial helper error triggers rollback' 1 lc_partial
assert_eq 'legacy helper error restores exact source bytes' "$LC_HASH" "$(git hash-object "$LC_ROOT/spec/a_spec.rb")"
assert_eq 'legacy rollback preserves unrelated bytes' unrelated "$(cat "$LC_ROOT/unrelated.txt")"
rm -rf "$LC_ROOT"
lc_fixture
cat > "$LC_ROOT/spec/b_spec.rb" <<'RB'
RSpec.describe "Other" do
  it "retained", skip: "REMOVED by other" do
    expect(1).to eq(0)
  end
end
RB
LC_OTHER="$(git hash-object "$LC_ROOT/spec/b_spec.rb")"
assert_ok 'Prism feature filter removes only selected feature' ruby "$LC_HELPER" --feature one "$LC_ROOT/spec/a_spec.rb" "$LC_ROOT/spec/b_spec.rb"
assert_eq 'Prism feature filter preserves other feature exact bytes' "$LC_OTHER" "$(git hash-object "$LC_ROOT/spec/b_spec.rb")"
rm -rf "$LC_ROOT"
lc_fixture
LC_HASH="$(git hash-object "$LC_ROOT/spec/a_spec.rb")"
cat > "$LC_ROOT/fake-runner" <<'SH'
#!/usr/bin/env bash
out=''
args=("$@")
while [[ $# -gt 0 ]]; do case "$1" in --out) out="$2";shift 2;; *) shift;; esac;done
rspec "${args[@]}" || exit $?
if ! grep -qF 'it "gone"' spec/a_spec.rb;then
  jq '.examples += [(.examples[0] | .id="unexpected[1:999]")]' "$out" > "$out.tmp"
  mv "$out.tmp" "$out"
fi
SH
chmod +x "$LC_ROOT/fake-runner"
sed 's/test_command: rspec/test_command: .\/fake-runner/' "$LC_ROOT/.kaba/config.yml" > "$LC_ROOT/config-tmp"
mv "$LC_ROOT/config-tmp" "$LC_ROOT/.kaba/config.yml"
assert_fail 'legacy incorrect remaining count triggers rollback' 1 lc_run
assert_eq 'legacy count error restores exact bytes' "$LC_HASH" "$(git hash-object "$LC_ROOT/spec/a_spec.rb")"
rm -rf "$LC_ROOT"
lc_fixture
sed 's/expect(1).to eq(1)/expect(File.read(__FILE__)).to match(\/^[[:space:]]*it "gone"\/)/' "$LC_ROOT/spec/a_spec.rb" > "$LC_ROOT/source-tmp"
mv "$LC_ROOT/source-tmp" "$LC_ROOT/spec/a_spec.rb"
git -C "$LC_ROOT" add spec/a_spec.rb
git -C "$LC_ROOT" -c user.name=Test -c user.email=test@example.test commit -qm 'verification fixture'
LC_HASH="$(git hash-object "$LC_ROOT/spec/a_spec.rb")"
assert_fail 'legacy real suite failure triggers rollback' 1 lc_run
assert_eq 'legacy suite failure restores exact bytes' "$LC_HASH" "$(git hash-object "$LC_ROOT/spec/a_spec.rb")"
assert_eq 'legacy failed suite keeps unrelated contents' unrelated "$(cat "$LC_ROOT/unrelated.txt")"
rm -rf "$LC_ROOT"
