#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
GO_RUNNER="$SCRIPT_DIR/../scripts/test-runner.sh"
export GOCACHE="${GOCACHE:-/private/tmp/kaba-go-build}"
if ! command -v go >/dev/null 2>&1; then
  _fail "Go runner behavior tests require Go" 'go not found'
  return 0
fi
GRT_REPO="$(mktemp -d)"
git -C "$GRT_REPO" init -q
mkdir -p "$GRT_REPO/.kaba" "$GRT_REPO/features/one"
cat > "$GRT_REPO/.kaba/config.yml" <<'EOF'
test_runner: go
test_command: go test ./...
feature_dir: features/
linter_command: "true"
test_write_allow: ["**/*_test.go", "**/testdata/**", "features/**", "go.mod", "go.sum"]
test_write_exclude: []
implement_write_allow: ["**"]
implement_write_exclude: ["**/*_test.go", "**/testdata/**"]
EOF
printf 'module example.com/runner\n\ngo 1.23\n' > "$GRT_REPO/go.mod"
cat > "$GRT_REPO/runner_test.go" <<'EOF'
package runner
import "testing"
func TestPass(t *testing.T) {}
func TestFail(t *testing.T) { t.Fatal("real red") }
func TestSkip(t *testing.T) { t.Skip("REMOVED by one") }
EOF
grt_run() { (cd "$GRT_REPO" && FEATURE_DIR="$GRT_REPO/features/one" bash "$GO_RUNNER" "$@"); }
assert_ok "real Go red suite yields valid runner results" grt_run run --phase baseline
grt_json="$(grt_run run --phase baseline 2>/dev/null || true)"
assert_eq "Go runner maps real pass fail skip outcomes" 'failed,passed,pending' "$(printf '%s' "$grt_json" | jq -r '[.examples[].status] | sort | join(",")' 2>/dev/null)"
assert_eq "Go runner records uncached execution context" '1' "$(printf '%s' "$grt_json" | jq -r '.context.count' 2>/dev/null)"
grt_without_ruby() { (ruby() { return 99; }; export -f ruby; grt_run run --phase baseline); }
assert_ok "Go snapshots execute without a Ruby toolchain" grt_without_ruby
cat > "$GRT_REPO/runner_test.go" <<'EOF'
package runner
import ("os"; "testing")
func TestExecute(t *testing.T) {
  f, err := os.OpenFile("runs", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
  if err != nil { t.Fatal(err) }
  defer f.Close()
  if _, err := f.WriteString("run\n"); err != nil { t.Fatal(err) }
}
EOF
assert_ok "first real green Go execution succeeds" grt_run run --phase baseline
assert_ok "second real green Go execution succeeds" grt_run run --phase baseline
assert_eq "snapshot executions bypass Go test result caching" 2 "$(wc -l < "$GRT_REPO/runs" | tr -d ' ')"
grt_capture() { (cd "$GRT_REPO" && FEATURE_DIR="$GRT_REPO/features/one" bash "$SCRIPT_DIR/../scripts/snapshot-tests.sh" capture baseline); }
assert_ok "Go snapshot capture uses the neutral adapter" grt_capture
assert_eq "Go snapshot preserves package and runtime identity" 'example.com/runner::TestExecute' "$(jq -r '.examples[0].id' "$GRT_REPO/features/one/snapshots/baseline.json")"
cat > "$GRT_REPO/runner_test.go" <<'EOF'
package runner
import ("os"; "testing")
func TestMain(m *testing.M) { os.Exit(0) }
func TestNever(t *testing.T) { t.Fatal("must execute") }
EOF
assert_fail "TestMain early success cannot produce an empty snapshot" 1 grt_run run --phase baseline
sed 's/os.Exit(0)/os.Exit(2)/' "$GRT_REPO/runner_test.go" > "$GRT_REPO/runner.tmp"
mv "$GRT_REPO/runner.tmp" "$GRT_REPO/runner_test.go"
assert_fail "TestMain package error is not an individual red test" 1 grt_run run --phase baseline
cat > "$GRT_REPO/runner_test.go" <<'EOF'
package runner
import "testing"
func TestCompile(t *testing.T) { missing() }
EOF
assert_fail "compilation failure cannot produce synthetic red cases" 1 grt_run run --phase baseline
assert_fail "user overlays are rejected before execution" 1 env GOFLAGS=-overlay=foreign.json bash -c 'cd "$1"; bash "$2" run --phase post-test' _ "$GRT_REPO" "$GO_RUNNER"
sed 's@go test ./...@go test ./... -run TestPass@' "$GRT_REPO/.kaba/config.yml" > "$GRT_REPO/.kaba/config.tmp"
mv "$GRT_REPO/.kaba/config.tmp" "$GRT_REPO/.kaba/config.yml"
assert_stderr_match "narrowed Go test selection is rejected explicitly" 'narrow|unsupported|not supported' grt_run identities --phase baseline
rm -rf "$GRT_REPO"
