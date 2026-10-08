#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
GO_CONTEXT_RUNNER="$SCRIPT_DIR/../scripts/test-runner.sh"
export GOCACHE="${GOCACHE:-/private/tmp/kaba-go-build}"
export GOENV=off GOFLAGS=
GCT_REAL_GO="$(command -v go)"
export GCT_REAL_GO
GCT_REPO="$(mktemp -d)"
GCT_REPO="$(cd "$GCT_REPO" && pwd -P)"
git -C "$GCT_REPO" init -q
mkdir -p "$GCT_REPO/.kaba" "$GCT_REPO/bin" "$GCT_REPO/subdir"
gct_config() {
  cat > "$GCT_REPO/.kaba/config.yml" <<EOF
test_runner: go
test_command: $1 test ./...
feature_dir: features/
linter_command: "true"
test_write_allow: ["**/*_test.go"]
test_write_exclude: []
implement_write_allow: ["**"]
implement_write_exclude: ["**/*_test.go"]
EOF
}
gct_config go
printf 'module example.com/context\n\ngo 1.23\n' > "$GCT_REPO/go.mod"
cat > "$GCT_REPO/value.go" <<'EOF'
package context
func Value() int { return 0 }
EOF
cat > "$GCT_REPO/value_test.go" <<'EOF'
package context
import "testing"
func TestValue(t *testing.T) {
  if Value() != 1 { t.Fatal("production value is zero") }
}
EOF
cat > "$GCT_REPO/replacement.txt" <<'EOF'
package context
func Value() int { return 1 }
EOF
jq -n --arg source "$GCT_REPO/value.go" --arg replacement "$GCT_REPO/replacement.txt" \
  '{Replace:{($source):$replacement}}' > "$GCT_REPO/overlay.json"
printf 'GOFLAGS=-overlay=%s/overlay.json\n' "$GCT_REPO" > "$GCT_REPO/goenv"
gct_persisted_run() {
  (cd "$GCT_REPO" && env -u GOFLAGS GOENV="$GCT_REPO/goenv" bash "$GO_CONTEXT_RUNNER" "$@")
}
assert_fail "baseline rejects persisted GOENV overlay with shell GOFLAGS unset" 1 gct_persisted_run run --phase baseline
assert_stderr_match "persisted overlay rejection identifies effective GOFLAGS" 'GOFLAGS.*not supported' gct_persisted_run identities --phase baseline
assert_fail "post-implementation rejects persisted GOENV overlay" 1 gct_persisted_run run --phase post-impl

# The configured executable delegates to real Go and records which tool handles discovery.
cat > "$GCT_REPO/bin/go" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$PWD" "$*" >> "$GCT_TOOL_LOG"
exec "$GCT_REAL_GO" "$@"
EOF
chmod +x "$GCT_REPO/bin/go"
export GCT_TOOL_LOG="$GCT_REPO/tool.log"
gct_run() { (cd "$GCT_REPO" && bash "$GO_CONTEXT_RUNNER" "$@"); }
gct_config ./bin/go
assert_ok "relative configured Go executable discovers from consumer root" gct_run identities --phase baseline
assert_ok "relative configured Go executable runs the full red suite" gct_run run --phase baseline
gct_from_subdir() { (cd "$GCT_REPO/subdir" && bash "$GO_CONTEXT_RUNNER" identities --phase baseline); }
assert_ok "relative configured Go executable resolves from root in a subdirectory" gct_from_subdir
gct_config "$GCT_REPO/bin/go"
: > "$GCT_TOOL_LOG"
assert_ok "absolute configured Go executable discovers source inventory" gct_run identities --phase baseline
assert_stdout_match "source discovery uses the configured executable in consumer root" "^$GCT_REPO list " cat "$GCT_TOOL_LOG"
# Equal source identities with different effective compiler settings cannot compare.
mkdir -p "$GCT_REPO/features/one/snapshots"
printf '{"version":3,"entries":[]}\n' > "$GCT_REPO/features/one/test-plan.json"
gct_context_snapshot() {
  (cd "$GCT_REPO" && CGO_CFLAGS="$1" bash "$GO_CONTEXT_RUNNER" identities --phase baseline) |
    jq --arg name "$2" '. + {version:2,runner_schema:.schema,metadata:{name:$name},examples:[.examples[] + {status:"passed"}]}' > "$GCT_REPO/features/one/snapshots/$2.json"
}
cp "$GCT_REPO/features/one/test-plan.json" "$GCT_REPO/features/one/snapshots/test-plan.lock.json"
gct_context_snapshot '-O0' baseline
gct_context_snapshot '-O2' post-test
gct_compare() { (cd "$GCT_REPO" && FEATURE_DIR="$GCT_REPO/features/one" bash "${GO_CONTEXT_RUNNER%test-runner.sh}snapshot-tests.sh" compare post-test); }
assert_stderr_match 'effective compiler flags change blocks snapshot comparison' 'context mismatch' gct_compare
assert_stdout_match 'runner reports effective compiler flags' '"CGO_CFLAGS": "-O0"' cat "$GCT_REPO/features/one/snapshots/baseline.json"
rm -rf "$GCT_REPO"
