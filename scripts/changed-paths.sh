#!/usr/bin/env bash
# Git-visible changed paths, NUL delimited. Renames retain both endpoints;
# dirty includes staged, unstaged and untracked paths, including absent leaves.
kaba_changed_paths() {
  local root
  case "${1:-}" in staged|dirty) ;; *) printf 'ERROR: changed paths mode must be staged or dirty\n' >&2; return 1 ;; esac
  root="$(git rev-parse --show-toplevel)" || return 1
  git -C "$root" diff --cached --name-only --no-renames --diff-filter=ACMRDTU -z -- || return 1
  if [ "$1" = dirty ]; then
    git -C "$root" diff --name-only --no-renames --diff-filter=ACMRDTU -z -- || return 1
    git -C "$root" ls-files --others --exclude-standard -z -- || return 1
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
  kaba_changed_paths "${1:-}"
fi
