#!/usr/bin/env bash
# Zero-dependency assertion helpers. Sourced by every *_test.sh.
# Each helper prints one result line and increments the pass/fail counters.
: "${KABA_TEST_PASS:=0}"
: "${KABA_TEST_FAIL:=0}"

_pass() { KABA_TEST_PASS=$((KABA_TEST_PASS + 1)); printf '  %-58s PASS\n' "$1"; }
_fail() {
  KABA_TEST_FAIL=$((KABA_TEST_FAIL + 1))
  printf '  %-58s FAIL\n' "$1"
  [ -n "${2:-}" ] && printf '    %s\n' "$2"
  return 0
}

assert_ok() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then _pass "$label"; else _fail "$label" "expected exit 0, got $?"; fi
}

assert_fail() {
  local label="$1" want="$2"; shift 2
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$want" ]; then _pass "$label"; else _fail "$label" "expected exit $want, got $got"; fi
}

assert_stdout_match() {
  local label="$1" re="$2"; shift 2
  local out; out="$("$@" 2>/dev/null || true)"
  case "$out" in
    *) if printf '%s' "$out" | grep -Eq "$re"; then _pass "$label"
       else _fail "$label" "stdout did not match /$re/; got: $out"; fi ;;
  esac
}

assert_stderr_match() {
  local label="$1" re="$2"; shift 2
  local err; err="$("$@" 2>&1 >/dev/null || true)"
  if printf '%s' "$err" | grep -Eq "$re"; then _pass "$label"
  else _fail "$label" "stderr did not match /$re/; got: $err"; fi
}

assert_eq() {
  local label="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then _pass "$label"; else _fail "$label" "expected '$want', got '$got'"; fi
}

assert_file_exists() {
  local label="$1" path="$2"
  if [ -e "$path" ]; then _pass "$label"; else _fail "$label" "no such file: $path"; fi
}
