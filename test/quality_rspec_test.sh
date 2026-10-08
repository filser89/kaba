#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
QUALITY="$SCRIPT_DIR/../scripts/banned-patterns.sh"
d="$(mktemp -d)"
git -C "$d" init -q -b master
mkdir -p "$d/.kaba" "$d/spec" "$d/vendor"
cat > "$d/.kaba/config.yml" <<'YAML'
test_runner: rspec
test_command: ./fake-rspec
feature_dir: features/
linter_command: true
test_write_allow: ['spec/**', 'features/**']
test_write_exclude: []
implement_write_allow: ['**']
implement_write_exclude: ['spec/**']
YAML
cat > "$d/fake-rspec" <<'SH'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
 if [ "$1" = --out ]; then printf '{"examples":[{"id":"./spec/ok_spec.rb[1:1]","file_path":"./spec/ok_spec.rb","line_number":1,"full_description":"ok"}]}' > "$2"; exit 0; fi
 shift
done
SH
chmod +x "$d/fake-rspec"
printf 'it "ok" do\n expect(true).to eq(true)\nend\n' > "$d/spec/ok_spec.rb"
printf 'expect(x).to receive(:danger)\n' > "$d/vendor/other_spec.rb"
run_quality_rspec() { (cd "$d" && bash "$QUALITY" --json); }
assert_ok 'explicit RSpec scans runner-selected files' run_quality_rspec
assert_stdout_match 'explicit RSpec reports selected file count' '"files_scanned": 1' run_quality_rspec
printf 'expect(x).to receive(:danger)\n' >> "$d/spec/ok_spec.rb"
assert_fail 'explicit RSpec retains matcher bans' 1 run_quality_rspec
rm -rf "$d"
