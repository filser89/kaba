#!/usr/bin/env bash
# Mechanical half of /kaba:init: writes config, creates the feature dir, wires the
# git hooks path, and gitignores runner artifacts. Detection and human confirmation
# belong to the command file; this script only performs writes it was told to perform.
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/config.sh"

test_dir=""; test_command=""; feature_dir=""; linter_command=""
test_writable=""; rules_files=""; runner_artifacts=""; force=""
test_runner=""; explicit=""
test_write_allow=(); test_write_exclude=(); implement_write_allow=(); implement_write_exclude=()
seen_test_allow=""; seen_test_exclude=""; seen_implement_allow=""; seen_implement_exclude=""

while [ $# -gt 0 ]; do
  [ "$#" -gt 1 ] || [ "$1" = --force ] || kaba_die "missing value for $1"
  case "$1" in
    --test-runner) test_runner="$2"; shift 2 ;;
    --test-write-allow) explicit=1; seen_test_allow=1; [ -z "$2" ] || test_write_allow+=("$2"); shift 2 ;;
    --test-write-exclude) explicit=1; seen_test_exclude=1; [ -z "$2" ] || test_write_exclude+=("$2"); shift 2 ;;
    --implement-write-allow) explicit=1; seen_implement_allow=1; [ -z "$2" ] || implement_write_allow+=("$2"); shift 2 ;;
    --implement-write-exclude) explicit=1; seen_implement_exclude=1; [ -z "$2" ] || implement_write_exclude+=("$2"); shift 2 ;;
    --test-dir)         test_dir="$2"; shift 2 ;;
    --test-command)     test_command="$2"; shift 2 ;;
    --feature-dir)      feature_dir="$2"; shift 2 ;;
    --linter-command)   linter_command="$2"; shift 2 ;;
    --test-writable)    test_writable="$2"; shift 2 ;;
    --rules-files)      rules_files="$2"; shift 2 ;;
    --runner-artifact)  runner_artifacts="$runner_artifacts $2"; shift 2 ;;
    --force)            force=1; shift ;;
    *) kaba_die "unknown argument: $1" ;;
  esac
done

for pair in "test_command:$test_command" \
            "feature_dir:$feature_dir" "linter_command:$linter_command"; do
  [ -n "${pair#*:}" ] || kaba_die "missing required argument --${pair%%:*}"
done

slash() { case "$1" in */) printf '%s' "$1" ;; *) printf '%s/' "$1" ;; esac; }
feature_dir="$(slash "$feature_dir")"
if [ -n "$explicit" ]; then
  [ -z "$test_dir$test_writable" ] || kaba_die 'cannot mix legacy test_dir/test_writable with explicit permissions'
  [ -n "$test_runner" ] || kaba_die 'explicit permissions require --test-runner'
  for seen in "$seen_test_allow" "$seen_test_exclude" "$seen_implement_allow" "$seen_implement_exclude"; do
    [ -n "$seen" ] || kaba_die 'explicit permissions require all four allow/exclude lists (use an empty value for empty exclusions)'
  done
else
  [ -n "$test_dir" ] || kaba_die 'missing required argument --test-dir'
  test_dir="$(slash "$test_dir")"
fi
root="$(kaba_repo_root)"

# Never silently clobber: the config may carry hand edits (supported), and an
# existing non-empty feature dir may belong to another tool (Cucumber).
if [ -f "$root/.kaba/config.yml" ] && [ -z "$force" ]; then
  kaba_die "$root/.kaba/config.yml already exists — edit it by hand, or pass --force to rewrite it"
fi
fdir="$root/${feature_dir%/}"
if [ -d "$fdir" ] && [ -n "$(ls -A "$fdir")" ] && [ -z "$force" ]; then
  kaba_die "$fdir exists and is not empty — if another tool owns it (Cucumber?), choose a different feature_dir; pass --force to adopt it"
fi

fmt_list() { printf '[%s]' "$(printf '%s' "$1" | sed 's/,[[:space:]]*/, /g')"; }

yaml_scalar() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }
write_list() {
  local key="$1"; shift
  if [ "$#" -eq 0 ]; then printf '%s: []\n' "$key"; return; fi
  printf '%s:\n' "$key"
  for value in "$@"; do printf '  - %s\n' "$(yaml_scalar "$value")"; done
}
# Validate the candidate through the same loader before mutating the project.
candidate="$(mktemp -d "${TMPDIR:-/tmp}/kaba-init.XXXXXX")"
trap 'rm -rf "$candidate"' EXIT
mkdir -p "$candidate/.kaba"
{
  echo "# .kaba/config.yml"
  if [ -n "$test_runner" ]; then printf 'test_runner: %s\n' "$(yaml_scalar "$test_runner")"; fi
  if [ -n "$explicit" ]; then
    write_list test_write_allow "${test_write_allow[@]+"${test_write_allow[@]}"}"
    write_list test_write_exclude "${test_write_exclude[@]+"${test_write_exclude[@]}"}"
    write_list implement_write_allow "${implement_write_allow[@]+"${implement_write_allow[@]}"}"
    write_list implement_write_exclude "${implement_write_exclude[@]+"${implement_write_exclude[@]}"}"
  else
    printf 'test_dir:       %s\n' "$test_dir"
    if [ -n "$test_writable" ]; then printf 'test_writable:  %s\n' "$(fmt_list "$test_writable")"; fi
  fi
  printf 'test_command:   %s\n' "$(yaml_scalar "$test_command")"
  printf 'feature_dir:    %s\n' "$(yaml_scalar "$feature_dir")"
  printf 'linter_command: %s\n' "$(yaml_scalar "$linter_command")"
  if [ -n "$rules_files" ]; then printf 'rules_files:    %s\n' "$(fmt_list "$rules_files")"; fi
} > "$candidate/.kaba/config.yml"
(kaba_repo_root() { printf '%s\n' "$candidate"; }; kaba_load_config)

# Hooks are a committed shim, never a path into the plugin install: a relocated
# plugin must fail loudly at the shim, not silently via a dangling hooksPath (D10).
existing_hooks="$(git -C "$root" config core.hooksPath 2>/dev/null || true)"
if [ -n "$existing_hooks" ] && [ "$existing_hooks" != ".kaba/hooks" ] && [ -z "$force" ]; then
  kaba_die "core.hooksPath is already '$existing_hooks' (husky/lefthook?) — integrate by hand, or pass --force to take it over"
fi

mkdir -p "$root/.kaba" "$fdir"
cp "$candidate/.kaba/config.yml" "$root/.kaba/config.yml"

mkdir -p "$root/.kaba/hooks"
cp "$SCRIPT_DIR/hooks/pre-commit" "$root/.kaba/hooks/pre-commit"
chmod +x "$root/.kaba/hooks/pre-commit"

git -C "$root" config core.hooksPath ".kaba/hooks"
git -C "$root" config kaba.scriptdir "$SCRIPT_DIR"

# Verify, do not assume — a silently absent hooks path is the hazard D5 exists to close.
actual="$(git -C "$root" config core.hooksPath || true)"
[ "$actual" = ".kaba/hooks" ] || kaba_die "failed to set core.hooksPath (got '$actual')"
[ -x "$root/.kaba/hooks/pre-commit" ] || kaba_die "failed to install the pre-commit shim"

# Session-lock state is local machine state.
touch "$root/.gitignore"
grep -qxF '/.kaba/session-lock' "$root/.gitignore" 2>/dev/null \
  || printf '/.kaba/session-lock\n' >> "$root/.gitignore"

for artifact in $runner_artifacts; do
  grep -qxF "/$artifact" "$root/.gitignore" 2>/dev/null \
    || printf '/%s\n' "$artifact" >> "$root/.gitignore"
done

echo "kaba initialized:"
echo "  config:     $root/.kaba/config.yml"
echo "  features:   $root/$feature_dir"
echo "  hook shim:  $root/.kaba/hooks/pre-commit (commit this)"
echo "  scriptdir:  $SCRIPT_DIR"
