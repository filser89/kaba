#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
export GOCACHE="${GOCACHE:-${TMPDIR:-/tmp}/kaba-go-build}"
go_inventory() { (cd "$SCRIPT_DIR/../scripts/go" && go run . identities --root "$go_fixture"); }
go_fixture="$(mktemp -d)"
printf 'module example/demo\n\ngo 1.23\n' > "$go_fixture/go.mod"
cat > "$go_fixture/pay_test.go" <<'EOF'
package demo
import "testing"
func TestPay(t *testing.T) {
 t.Fatal("setup fails before registration")
 t.Run("one",func(t *testing.T){t.Error("red")})
}
EOF
cat > "$go_fixture/external_test.go" <<'EOF'
package demo_test
import "testing"
func TestExternal(t *testing.T) { t.Error("red") }
EOF
assert_stdout_match "public discovery sees hidden subtest" 'example/demo::TestPay/one' go_inventory
assert_stdout_match "public discovery sees external package test" 'example/demo::TestExternal' go_inventory
printf 'package demo\nimport "testing"\nfunc TestDynamic(t *testing.T){t.Run(dynamicName,func(t *testing.T){})}\n' > "$go_fixture/dynamic_test.go"
assert_fail "public discovery rejects dynamic registrations" 1 go_inventory
rm -rf "$go_fixture"
