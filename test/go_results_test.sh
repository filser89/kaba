#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
GR_DIR="$(mktemp -d)"
GR_CONVERTER="$SCRIPT_DIR/../scripts/adapters/go-results.sh"
cat > "$GR_DIR/expected.json" <<'EOF'
[{"id":"example::TestRows","test_name":"TestRows","package":"example","is_group":true},
 {"id":"example::TestRows/pass","test_name":"TestRows/pass","package":"example","is_group":false,"file_path":"rows_test.go","digest":"a"},
 {"id":"example::TestRows/fail","test_name":"TestRows/fail","package":"example","is_group":false,"file_path":"rows_test.go","digest":"b"},
 {"id":"example::TestRows/skip","test_name":"TestRows/skip","package":"example","is_group":false,"file_path":"rows_test.go","digest":"c"}]
EOF
cat > "$GR_DIR/events.jsonl" <<'EOF'
{"Action":"start","Package":"example"}
{"Action":"run","Package":"example","Test":"TestRows"}
{"Action":"run","Package":"example","Test":"TestRows/pass"}
{"Action":"pause","Package":"example","Test":"TestRows/pass"}
{"Action":"run","Package":"example","Test":"TestRows/fail"}
{"Action":"fail","Package":"example","Test":"TestRows/fail"}
{"Action":"run","Package":"example","Test":"TestRows/skip"}
{"Action":"skip","Package":"example","Test":"TestRows/skip"}
{"Action":"cont","Package":"example","Test":"TestRows/pass"}
{"Action":"pass","Package":"example","Test":"TestRows/pass"}
{"Action":"fail","Package":"example","Test":"TestRows"}
{"Action":"fail","Package":"example"}
EOF
gr_convert() { bash "$GR_CONVERTER" "$GR_DIR/expected.json" "$GR_DIR/events.jsonl" "${1:-1}"; }
assert_ok "complete interleaved red Go cases are valid results" gr_convert
gr_out="$(gr_convert 2>/dev/null || true)"
assert_eq "Go parent outcome is not a fourth example" 3 "$(printf '%s' "$gr_out" | jq '.examples | length' 2>/dev/null)"
assert_eq "Go skip maps to workflow pending" pending "$(printf '%s' "$gr_out" | jq -r '.examples[] | select(.test_name=="TestRows/skip") | .status' 2>/dev/null)"
cp "$GR_DIR/events.jsonl" "$GR_DIR/good.jsonl"
sed '/"Test":"TestRows\/skip"/d' "$GR_DIR/good.jsonl" > "$GR_DIR/events.jsonl"
assert_fail "missing child outcomes invalidate a run" 1 gr_convert
printf '%s\n' '{"Action":"start","Package":"example"}' '{"Action":"pass","Package":"example"}' > "$GR_DIR/events.jsonl"
assert_fail "successful TestMain exit cannot hide expected tests" 1 gr_convert 0
printf '%s\n' '{"Action":"start","Package":"example"}' '{"Action":"fail","Package":"example"}' > "$GR_DIR/events.jsonl"
assert_fail "package failure cannot synthesize individual red tests" 1 gr_convert
cp "$GR_DIR/good.jsonl" "$GR_DIR/events.jsonl"
assert_fail "unexpected process error invalidates complete results" 1 gr_convert 2
printf '%s\n' '{malformed' >> "$GR_DIR/events.jsonl"
assert_fail "malformed Go events invalidate capture" 1 gr_convert
sed '$d' "$GR_DIR/good.jsonl" > "$GR_DIR/events.jsonl"
assert_fail "truncated package outcomes invalidate capture" 1 gr_convert
cat "$GR_DIR/good.jsonl" "$GR_DIR/good.jsonl" > "$GR_DIR/events.jsonl"
assert_fail "duplicate terminal test outcomes invalidate capture" 1 gr_convert
printf '%s\n' '{"Action":"build-fail","ImportPath":"example"}' > "$GR_DIR/events.jsonl"
assert_fail "build failure invalidates capture before test mapping" 1 gr_convert
sed 's/"Action":"fail","Package":"example"}/"Action":"pass","Package":"example"}/' "$GR_DIR/good.jsonl" > "$GR_DIR/events.jsonl"
assert_fail "package success cannot contradict an individual failure" 1 gr_convert
printf '%s\n' '{"Action":"build-surprise","ImportPath":"example"}' > "$GR_DIR/events.jsonl"
printf '%s\n' '[]' > "$GR_DIR/expected.json"
assert_fail "unknown build events cannot masquerade as an empty run" 1 gr_convert 0
rm -rf "$GR_DIR"
