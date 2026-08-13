#!/usr/bin/env bash
# Mechanical enforcement of the two-session boundary. Write rules are complements
# derived from config, never hand-maintained lists:
#   implement  may write everything except test_dir
#   test       may write only test_dir, feature_dir, and test_writable
# Single home for the path rules; the PreToolUse guard and the pre-commit hook both call `check`.
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/config.sh"

kaba_load_config
LOCK_FILE="$KABA_REPO_ROOT/.kaba/session-lock"

current_mode() {
  if [ -f "$LOCK_FILE" ]; then tr -d '[:space:]' < "$LOCK_FILE"; else echo "off"; fi
}

carve_outs() {
  # `[ -n … ] && printf` would return 1 on an empty list and kill the whole
  # script under `set -e` — return 0 explicitly.
  [ -n "$KABA_TEST_WRITABLE" ] || return 0
  printf '%s\n' "$KABA_TEST_WRITABLE" | sed 's/^/    /'
}

# A trailing slash means the whole subtree; anything else is an exact path.
matches_writable() {
  local rel="$1" entry
  [ -n "$KABA_TEST_WRITABLE" ] || return 1
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "$entry" in
      */) case "$rel" in "$entry"*) return 0 ;; esac ;;
      *)  [ "$rel" = "$entry" ] && return 0 ;;
    esac
  done <<EOF
$KABA_TEST_WRITABLE
EOF
  return 1
}

# Anchored subtree test — "spec/" must never match "specs/".
under_dir() {
  case "$1" in "$2"*) return 0 ;; *) return 1 ;; esac
}

# Absolute paths may be symlinked (e.g. /var vs /private/var on macOS), and the
# leaf usually doesn't exist yet — a check runs on a hypothetical write target.
# Walk up to the nearest existing ancestor, canonicalize that physically, then
# re-append the (possibly nonexistent) tail.
_kaba_canon() {
  local p="$1" tail=""
  while [ -n "$p" ] && [ "$p" != "/" ] && [ ! -d "$p" ]; do
    tail="$(basename "$p")${tail:+/$tail}"
    p="$(dirname "$p")"
  done
  p="$(cd "$p" 2>/dev/null && pwd -P)" || return 1
  if [ "$p" = "/" ]; then printf '/%s' "$tail"; else printf '%s%s' "$p" "${tail:+/$tail}"; fi
}

cmd_set() {
  local mode="${1:-}"
  [ "$mode" = "test" ] || [ "$mode" = "implement" ] || kaba_die "mode must be 'test' or 'implement'"
  mkdir -p "$(dirname "$LOCK_FILE")"
  printf '%s\n' "$mode" > "$LOCK_FILE"
  echo "session-lock: $mode"
}

cmd_clear() { rm -f "$LOCK_FILE"; echo "session-lock: off"; }

cmd_status() {
  local mode; mode="$(current_mode)"
  echo "session-lock: $mode"
  if [ "$mode" = "test" ]; then
    echo "  test session may write: $KABA_TEST_DIR, $KABA_FEATURE_DIR, and these carve-outs:"
    carve_outs
  elif [ "$mode" = "implement" ]; then
    echo "  implementation session may write everything except $KABA_TEST_DIR"
  fi
}

cmd_check() {
  local mode; mode="$(current_mode)"
  [ "$mode" = "off" ] && exit 0
  [ "$mode" = "test" ] || [ "$mode" = "implement" ] \
    || kaba_die "invalid mode '$mode' in $LOCK_FILE — run session-lock.sh clear"

  local violations="" p rel c prev
  for p in "$@"; do
    rel="$p"
    # Lexical cleanup: strip leading ./ and collapse doubled slashes to a fixed point.
    while :; do
      prev="$rel"
      case "$rel" in *//*) rel="$(printf '%s' "$rel" | sed 's://*:/:g')" ;; esac
      case "$rel" in ./*) rel="${rel#./}" ;; esac
      [ "$rel" = "$prev" ] && break
    done
    # Walk-up canonicalization for absolute paths — see _kaba_canon.
    case "$rel" in
      /*) if c="$(_kaba_canon "$rel")"; then rel="$c"; fi ;;
    esac
    case "$rel" in "$KABA_REPO_ROOT"/*) rel="${rel#"$KABA_REPO_ROOT"/}" ;; esac
    # String prefix rules cannot resolve '..' — refuse it rather than mis-classify.
    case "/$rel/" in */../*)
      violations="$violations  $p  (refused: '..' segment — pass a normalized path)"$'\n'
      continue ;;
    esac
    case "$mode" in
      implement)
        under_dir "$rel" "$KABA_TEST_DIR" && violations="$violations  $rel"$'\n'
        ;;
      test)
        if under_dir "$rel" "$KABA_TEST_DIR" || under_dir "$rel" "$KABA_FEATURE_DIR" \
           || matches_writable "$rel"; then :
        else violations="$violations  $rel"$'\n'; fi
        ;;
    esac
  done

  if [ -n "$violations" ]; then
    {
      echo "session-lock VIOLATION (mode: $mode) — locked paths:"
      printf '%s' "$violations"
      if [ "$mode" = "implement" ]; then
        echo "The implementation session must not modify the test directory ($KABA_TEST_DIR)."
      else
        echo "The test session may write only $KABA_TEST_DIR, $KABA_FEATURE_DIR, and:"
        carve_outs
      fi
      echo "If this lock is stale: session-lock.sh status (or clear)"
    } >&2
    exit 1
  fi
  exit 0
}

case "${1:-}" in
  set)    shift; cmd_set "${1:-}" ;;
  clear)  cmd_clear ;;
  status) cmd_status ;;
  check)  shift; cmd_check "$@" ;;
  *)      echo "Usage: session-lock.sh <set test|implement | clear | status | check <path>...>" >&2; exit 1 ;;
esac
