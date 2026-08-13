#!/usr/bin/env bash
# Resolves the current feature from the git branch name and prints
# REPO_ROOT / FEATURE_DIR / FEATURE_SPEC as KEY=value lines.
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/config.sh"

kaba_load_config

branch="$(git -C "$KABA_REPO_ROOT" rev-parse --abbrev-ref HEAD)"

prefix=""
if [[ "$branch" =~ ^([0-9]{8}-[0-9]{6})- ]]; then
  prefix="${BASH_REMATCH[1]}"
elif [[ "$branch" =~ ^([0-9]{3})- ]]; then
  prefix="${BASH_REMATCH[1]}"
else
  echo "ERROR: not on a feature branch. Current branch: $branch" >&2
  echo "Feature branches are named like 001-feature-name or 20260813-091500-feature-name." >&2
  exit 1
fi

feature_root="$KABA_REPO_ROOT/${KABA_FEATURE_DIR%/}"
matches=()
for d in "$feature_root/$prefix"-*; do
  [ -d "$d" ] && matches+=("$d")
done

if [ "${#matches[@]}" -eq 0 ]; then
  kaba_die "no feature directory matching '$prefix-*' under $feature_root (branch: $branch)"
elif [ "${#matches[@]}" -gt 1 ]; then
  {
    echo "ERROR: multiple feature directories match '$prefix-*':"
    printf '  %s\n' "${matches[@]}"
    echo "Resolve the ambiguity before continuing."
  } >&2
  exit 1
fi

feature_dir="${matches[0]}"
printf 'REPO_ROOT=%s\n'    "$KABA_REPO_ROOT"
printf 'FEATURE_DIR=%s\n'  "$feature_dir"
printf 'FEATURE_SPEC=%s\n' "$feature_dir/spec.md"
