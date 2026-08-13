#!/usr/bin/env bash
# Allocates the next feature number, creates the branch and feature directory.
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/config.sh"

slug="${1:-}"
[ -n "$slug" ] || { echo "Usage: new-feature.sh <slug>" >&2; exit 1; }

kaba_load_config

feature_root="$KABA_REPO_ROOT/${KABA_FEATURE_DIR%/}"
mkdir -p "$feature_root"

# The next number clears BOTH existing feature dirs and local NNN- branches: a
# migrated project keeps old numbered branches after its feature dirs froze
# elsewhere, and `git checkout -b` dies on a name collision.
highest=0
bump() {
  case "$1" in
    [0-9][0-9][0-9]-*)
      # Strip leading zeros so 005 does not read as octal.
      n=$((10#${1%%-*}))
      [ "$n" -gt "$highest" ] && highest="$n"
      ;;
  esac
  return 0
}
for d in "$feature_root"/*; do
  [ -d "$d" ] || continue
  bump "$(basename "$d")"
done
while IFS= read -r b; do
  [ -n "$b" ] || continue
  bump "$b"
done <<EOF
$(git -C "$KABA_REPO_ROOT" for-each-ref refs/heads --format='%(refname:short)')
EOF

num="$(printf '%03d' $((highest + 1)))"
branch="$num-$slug"
dir="$feature_root/$branch"

[ -e "$dir" ] && kaba_die "$dir already exists"

git -C "$KABA_REPO_ROOT" checkout -q -b "$branch"
mkdir -p "$dir"

printf 'FEATURE_NUM=%s\n'  "$num"
printf 'BRANCH=%s\n'       "$branch"
printf 'FEATURE_DIR=%s\n'  "$dir"
printf 'FEATURE_SPEC=%s\n' "$dir/spec.md"
