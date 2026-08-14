#!/usr/bin/env bash
# Mechanical half of /kaba:init: writes config, creates the feature dir, wires the
# git hooks path, and gitignores runner artifacts. Detection and human confirmation
# belong to the command file; this script only performs writes it was told to perform.
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/config.sh"

test_dir=""; test_command=""; feature_dir=""; linter_command=""
test_writable=""; rules_files=""; runner_artifacts=""; force=""

while [ $# -gt 0 ]; do
  case "$1" in
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

for pair in "test_dir:$test_dir" "test_command:$test_command" \
            "feature_dir:$feature_dir" "linter_command:$linter_command"; do
  [ -n "${pair#*:}" ] || kaba_die "missing required argument --${pair%%:*}"
done

slash() { case "$1" in */) printf '%s' "$1" ;; *) printf '%s/' "$1" ;; esac; }
test_dir="$(slash "$test_dir")"; feature_dir="$(slash "$feature_dir")"

# Validate BEFORE writing anything, so a rejected run leaves no partial state.
case "$feature_dir" in "$test_dir"*) kaba_die "feature_dir '$feature_dir' is a prefix-path of test_dir '$test_dir'" ;; esac
case "$test_dir" in "$feature_dir"*) kaba_die "test_dir '$test_dir' is a prefix-path of feature_dir '$feature_dir'" ;; esac

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

mkdir -p "$root/.kaba" "$fdir"

fmt_list() { printf '[%s]' "$(printf '%s' "$1" | sed 's/,[[:space:]]*/, /g')"; }

{
  echo "# .kaba/config.yml — written by /kaba:init"
  printf 'test_dir:       %s\n' "$test_dir"
  printf 'test_command:   %s\n' "$test_command"
  printf 'feature_dir:    %s\n' "$feature_dir"
  # if-form, not `[ … ] && printf` — the && short-circuit returns 1 under set -e.
  if [ -n "$test_writable" ]; then printf 'test_writable:  %s\n' "$(fmt_list "$test_writable")"; fi
  printf 'linter_command: %s\n' "$linter_command"
  if [ -n "$rules_files" ]; then printf 'rules_files:    %s\n' "$(fmt_list "$rules_files")"; fi
} > "$root/.kaba/config.yml"

# Hooks are a committed shim, never a path into the plugin install: a relocated
# plugin must fail loudly at the shim, not silently via a dangling hooksPath (D10).
existing_hooks="$(git -C "$root" config core.hooksPath 2>/dev/null || true)"
if [ -n "$existing_hooks" ] && [ "$existing_hooks" != ".kaba/hooks" ] && [ -z "$force" ]; then
  kaba_die "core.hooksPath is already '$existing_hooks' (husky/lefthook?) — integrate by hand, or pass --force to take it over"
fi

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
