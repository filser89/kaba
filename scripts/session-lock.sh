#!/usr/bin/env bash
# Mechanical session boundary for tools, commits, and complete dirty change sets.
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/path-permissions.sh"
. "$SCRIPT_DIR/changed-paths.sh"

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
  if [ "$KABA_PERMISSION_MODE" = explicit ] && [ "$mode" != off ]; then
    echo "  $mode session permissions: ${KABA_CONFIG_FILE:-.kaba/config.yml}"
    return 0
  fi
  if [ "$mode" = "test" ]; then
    echo "  test session may write: $KABA_TEST_DIR, $KABA_FEATURE_DIR, and these carve-outs:"
    carve_outs
  elif [ "$mode" = "implement" ]; then
    echo "  implementation session may write everything except $KABA_TEST_DIR"
  fi
}

check_paths() {
  local mode="$1"; shift
  [ "$mode" = "off" ] && return 0
  [ "$mode" = "test" ] || [ "$mode" = "implement" ] \
    || kaba_die "invalid mode '$mode' in $LOCK_FILE — run session-lock.sh clear"

  local violations="" p classification
  for p in "$@"; do
    if ! classification="$(kaba_classify_path "$p")"; then
      violations="$violations  $p  (refused: invalid permission path)"$'\n'
      continue
    fi
    case "$mode:$classification" in
      test:test|test:shared|implement:implement|implement:shared) ;;
      *) violations="$violations  $p"$'\n' ;;
    esac
  done

  if [ -n "$violations" ]; then
    {
      echo "session-lock VIOLATION (mode: $mode) — locked paths:"
      printf '%s' "$violations"
      if [ "$KABA_PERMISSION_MODE" = explicit ]; then
        echo "The $mode session may write only paths allowed by its configured permissions."
      elif [ "$mode" = "implement" ]; then
        echo "The implementation session must not modify the test directory ($KABA_TEST_DIR)."
      else
        echo "The test session may write only $KABA_TEST_DIR, $KABA_FEATURE_DIR, and:"
        carve_outs
      fi
      echo "If this lock is stale: session-lock.sh status (or clear)"
    } >&2
    return 1
  fi
  return 0
}

# Read exactly one entry from a fixed recorded tree, never from the working tree.
# Index directory entries are implicit in their tracked descendants.
recorded_entry() {
  local tree="$1" path="$2" records record header name entry="" directory=0
  records="$(mktemp)" || return 1
  if [ "$tree" = index ]; then
    if ! git -C "$KABA_REPO_ROOT" --literal-pathspecs ls-files --stage -z -- "$path" > "$records"; then rm -f "$records"; return 1; fi
  else
    if ! git -C "$KABA_REPO_ROOT" --literal-pathspecs ls-tree -z "$tree" -- "$path" > "$records"; then rm -f "$records"; return 1; fi
  fi
  while IFS= read -r -d '' record; do
    header="${record%%$'\t'*}"; name="${record#*$'\t'}"
    if [ "$name" = "$path" ]; then
      if [ "$tree" = index ]; then
        # Unmerged entries have no single recorded target to authorize.
        [ "${header##* }" = 0 ] || { rm -f "$records"; return 1; }
        entry="${header% *}"
      else
        entry="${header/ blob / }"; entry="${entry/ tree / }"
      fi
    else
      case "$name" in "$path"/*) directory=1 ;; esac
    fi
  done < "$records"
  rm -f "$records"
  if [ -n "$entry" ]; then printf '%s' "$entry"
  elif [ "$directory" -eq 1 ]; then printf '040000 directory'; fi
}

# Relative link targets may contain . and ..; normalize their lexical permission
# path without consulting filesystem state. Actual traversal below follows each
# recorded ancestor before interpreting a subsequent .. component.
recorded_lexical_path() {
  local remaining="$1" relative="" component
  while [ -n "$remaining" ]; do
    component="${remaining%%/*}"
    if [ "$remaining" = "$component" ]; then remaining=""; else remaining="${remaining#*/}"; fi
    case "$component" in
      ''|.) ;;
      ..) [ -n "$relative" ] || { _kaba_path_error "historical target outside repository"; return 1; }
          case "$relative" in */*) relative="${relative%/*}" ;; *) relative="" ;; esac ;;
      *) relative="${relative:+$relative/}$component" ;;
    esac
  done
  printf '%s' "$relative"
}

# Each symlink expansion keeps its lexical ownership and reads targets and
# ancestors from the same HEAD/index tree, even if current targets still exist.
check_recorded_path() {
  local mode="$1" tree="$2" path="$3" depth="${4:-0}" following="${5:-0}"
  local relative classification remaining component prefix="" parent entry object blob target
  [ "$depth" -lt 64 ] || { printf 'ERROR: cyclic historical symlink: %s\n' "$path" >&2; return 1; }
  case "$path" in ''|*$'\n'*|*$'\r'*|*$'\t'*) _kaba_path_error "unsupported control character in historical target"; return 1 ;; esac
  case "$path" in
    "$KABA_REPO_ROOT"/*) path="${path#"$KABA_REPO_ROOT"/}" ;;
    /*) _kaba_path_error "historical target outside repository '$path'"; return 1 ;;
  esac
  relative="$(recorded_lexical_path "$path")" || return 1
  [ -n "$relative" ] || { _kaba_path_error "historical target is repository root"; return 1; }
  classification="$(_kaba_classify_relative "$relative")" || return 1
  case "$mode:$classification" in
    test:test|test:shared|implement:implement|implement:shared) ;;
    *) printf 'session-lock VIOLATION (mode: %s) — historical target: %s\n' "$mode" "$relative" >&2; return 1 ;;
  esac
  remaining="$path"
  while [ -n "$remaining" ]; do
    component="${remaining%%/*}"
    if [ "$remaining" = "$component" ]; then remaining=""; else remaining="${remaining#*/}"; fi
    case "$component" in
      ''|.) continue ;;
      ..) [ -n "$prefix" ] || { _kaba_path_error "historical target outside repository"; return 1; }
          case "$prefix" in */*) prefix="${prefix%/*}" ;; *) prefix="" ;; esac
          continue ;;
    esac
    parent="$prefix"; prefix="${prefix:+$prefix/}$component"
    entry="$(recorded_entry "$tree" "$prefix")" || return 1
    if [ "${entry%% *}" = 120000 ]; then
      object="${entry#* }"
      blob="$(mktemp)" || return 1
      if ! git -C "$KABA_REPO_ROOT" cat-file blob "$object" > "$blob"; then rm -f "$blob"; return 1; fi
      target=""
      if IFS= read -r -d '' target < "$blob"; then
        printf 'ERROR: unsupported NUL in historical symlink target: %s\n' "$prefix" >&2
        rm -f "$blob"; return 1
      fi
      rm -f "$blob"
      case "$target" in ''|*$'\n'*|*$'\r'*|*$'\t'*) _kaba_path_error "unsupported control character in historical target '$prefix'"; return 1 ;; esac
      case "$target" in /*) ;; *) target="${parent:+$parent/}$target" ;; esac
      check_recorded_path "$mode" "$tree" "$target${remaining:+/$remaining}" "$((depth + 1))" 1
      return $?
    fi
  done
  if [ "$following" -eq 1 ]; then
    entry="$(recorded_entry "$tree" "$prefix")" || return 1
    [ -n "$entry" ] || { printf 'ERROR: dangling historical symlink: %s\n' "$prefix" >&2; return 1; }
  fi
}

check_old_symlinks() {
  local mode="$1" path="$2"
  check_recorded_path "$mode" index "$path" || return 1
  if git -C "$KABA_REPO_ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then
    check_recorded_path "$mode" HEAD "$path" || return 1
  fi
  return 0
}

check_changes() {
  local kind="$1" mode="$2" inventory path result=0
  [ "$mode" = off ] && return 0
  case "$mode" in test|implement) ;; *) kaba_die "mode must be 'test', 'implement', or 'off'" ;; esac
  # Capture producer status before reading; process-substitution failures must
  # never turn an incomplete inventory into a passing gate.
  inventory="$(mktemp)" || return 1
  if ! kaba_changed_paths "$kind" > "$inventory"; then rm -f "$inventory"; return 1; fi
  while IFS= read -r -d '' path; do
    if ! check_paths "$mode" "$path"; then result=1; continue; fi
    check_old_symlinks "$mode" "$path" || result=1
  done < "$inventory"
  rm -f "$inventory"
  return "$result"
}

case "${1:-}" in
  set)    shift; cmd_set "${1:-}" ;;
  clear)  cmd_clear ;;
  status) cmd_status ;;
  check)  shift; check_paths "$(current_mode)" "$@" ;;
  check-staged) check_changes staged "${2:-$(current_mode)}" ;;
  check-dirty) check_changes dirty "${2:-$(current_mode)}" ;;
  *)      echo "Usage: session-lock.sh <set test|implement | clear | status | check <path>... | check-staged [mode] | check-dirty [mode]>" >&2; exit 1 ;;
esac
