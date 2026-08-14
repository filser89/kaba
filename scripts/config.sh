#!/usr/bin/env bash
# Shared config access for every kaba script. Reads .kaba/config.yml explicitly;
# never sniffs the project. Sourced, not executed.

kaba_die() { echo "ERROR: $*" >&2; exit 1; }

kaba_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null \
    || kaba_die "not inside a git repository — kaba requires git for its enforcement gates"
}

# Scalar lookup: strips the key, inline comments, surrounding whitespace, and quotes.
# (YAML comments require preceding whitespace, so 's/[[:space:]]#.*$//' is safe.)
_kaba_yaml_scalar() {
  sed -n "s/^${1}:[[:space:]]*//p" "$2" | head -1 \
    | sed 's/[[:space:]]#.*$//; s/[[:space:]]*$//; s/^"//; s/"$//'
}

# List lookup: accepts inline [a, b, c] or a block of "- item" lines. Prints one per line.
_kaba_yaml_list() {
  local key="$1" file="$2" inline
  inline="$(_kaba_yaml_scalar "$key" "$file")"
  case "$inline" in
    \[*\])
      printf '%s' "$inline" | tr -d '[]' | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$'
      ;;
    "")
      sed -n "/^${key}:[[:space:]]*$/,/^[^[:space:]-]/p" "$file" \
        | sed -n 's/^[[:space:]]*-[[:space:]]*//p' | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//'
      ;;
    *) printf '%s\n' "$inline" ;;
  esac
}

_kaba_slash() { case "$1" in */) printf '%s' "$1" ;; *) printf '%s/' "$1" ;; esac; }

kaba_load_config() {
  local root cfg
  root="$(kaba_repo_root)" || exit 1
  cfg="$root/.kaba/config.yml"
  [ -f "$cfg" ] || kaba_die "$cfg not found — run /kaba:init"

  KABA_TEST_DIR="$(_kaba_yaml_scalar test_dir "$cfg")"
  KABA_TEST_COMMAND="$(_kaba_yaml_scalar test_command "$cfg")"
  KABA_FEATURE_DIR="$(_kaba_yaml_scalar feature_dir "$cfg")"
  KABA_LINTER_COMMAND="$(_kaba_yaml_scalar linter_command "$cfg")"
  KABA_TEST_WRITABLE="$(_kaba_yaml_list test_writable "$cfg")"
  KABA_RULES_FILES="$(_kaba_yaml_list rules_files "$cfg")"

  [ -n "$KABA_TEST_DIR" ]        || kaba_die "$cfg: required key 'test_dir' is missing or empty"
  [ -n "$KABA_TEST_COMMAND" ]    || kaba_die "$cfg: required key 'test_command' is missing or empty"
  [ -n "$KABA_FEATURE_DIR" ]     || kaba_die "$cfg: required key 'feature_dir' is missing or empty"
  [ -n "$KABA_LINTER_COMMAND" ]  || kaba_die "$cfg: required key 'linter_command' is missing or empty"

  KABA_TEST_DIR="$(_kaba_slash "$KABA_TEST_DIR")"
  KABA_FEATURE_DIR="$(_kaba_slash "$KABA_FEATURE_DIR")"

  # Only plain repo-relative paths: a "./", "..", or absolute value would defeat the
  # anchored prefix matching downstream — permissively, which is the worst direction.
  local v
  for v in "$KABA_TEST_DIR" "$KABA_FEATURE_DIR"; do
    case "/$v" in
      //*|*/../*|*/./*)
        kaba_die "$cfg: test_dir and feature_dir must be plain repo-relative paths (got '$v')" ;;
    esac
  done

  # An overlapping pair would let one glob swallow the other, silently and permissively.
  case "$KABA_FEATURE_DIR" in "$KABA_TEST_DIR"*)
    kaba_die "$cfg: feature_dir '$KABA_FEATURE_DIR' is a prefix-path of test_dir '$KABA_TEST_DIR' — they must not overlap" ;;
  esac
  case "$KABA_TEST_DIR" in "$KABA_FEATURE_DIR"*)
    kaba_die "$cfg: test_dir '$KABA_TEST_DIR' is a prefix-path of feature_dir '$KABA_FEATURE_DIR' — they must not overlap" ;;
  esac

  KABA_REPO_ROOT="$root"
  export KABA_REPO_ROOT KABA_TEST_DIR KABA_TEST_COMMAND KABA_FEATURE_DIR \
         KABA_LINTER_COMMAND KABA_TEST_WRITABLE KABA_RULES_FILES
}
