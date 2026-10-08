#!/usr/bin/env bash
# Sourced after config. Inventory includes ignored files; permission patterns own paths.
. "$SCRIPT_DIR/path-permissions.sh"
. "$SCRIPT_DIR/changed-paths.sh"
kaba_protected_inventory() {
  local entries result=0
  entries="$(mktemp "${TMPDIR:-/tmp}/kaba-protected-entries.XXXXXX")" || return 1
  _kaba_protected_scan "$KABA_REPO_ROOT" "$entries" "$(cd "$KABA_REPO_ROOT" && pwd -P)" || result=$?
  if [[ "$result" -eq 0 ]]; then jq -s 'sort_by(.path)' "$entries" || result=$?; fi
  rm -f "$entries"
  return "$result"
}

# An alias can have protected descendants even when its directory is not owned
# by tests. Only traverse in-repository targets, classifying every descendant.
_kaba_protected_scan() {
  local directory="$1" entries="$2" ancestors="$3"
  local paths path rel lexical owner hash target resolved children physical_root result=0
  physical_root="$(cd "$KABA_REPO_ROOT" && pwd -P)" || return 1
  paths="$(mktemp "${TMPDIR:-/tmp}/kaba-protected-paths.XXXXXX")"
  if ! find -H "$directory" -path "$KABA_REPO_ROOT/.git" -prune -o \( -type f -o -type l \) -print0 > "$paths"; then rm -f "$paths"; return 1; fi
  while IFS= read -r -d '' path; do
    rel="${path#"$KABA_REPO_ROOT/"}"
    lexical="$(_kaba_classify_relative "$rel")" || { result=1; break; }
    target=''
    if [[ -L "$path" && -d "$path" ]]; then
      resolved="$(cd "$path" && pwd -P)" || { result=1; break; }
      case "$resolved" in
        "$physical_root"|"$physical_root"/*) ;;
        *) if [[ "$lexical" == test ]]; then echo "ERROR: protected directory outside repository: $rel" >&2; result=1; break; fi; continue ;;
      esac
      owner="$(kaba_classify_path "$rel" 2>/dev/null)" || owner=none
      children="$(mktemp "${TMPDIR:-/tmp}/kaba-protected-children.XXXXXX")" || { result=1; break; }
      case $'\n'"$ancestors"$'\n' in
        *$'\n'"$resolved"$'\n'*)
          if [[ "$lexical" == test ]]; then
            echo "ERROR: cyclic protected directory alias: $rel" >&2
            rm -f "$children"; result=1; break
          fi ;;
        *)
          if [[ "$resolved" != "$physical_root/.git" ]]; then
            _kaba_protected_scan "$path" "$children" "$ancestors"$'\n'"$resolved" || { rm -f "$children"; result=1; break; }
          fi ;;
      esac
      if [[ "$owner" != test && ! -s "$children" ]]; then rm -f "$children"; continue; fi
      cat "$children" >> "$entries" || { rm -f "$children"; result=1; break; }
      rm -f "$children"
      target="$(readlink "$path")" || { result=1; break; }
      hash="$(printf '%s' "$target" | shasum -a 256)" || { result=1; break; }
    else
      case "$lexical" in
        test) owner="$(kaba_classify_path "$rel")" || { result=1; break; } ;;
        shared)
          # Shared paths only enter this inventory if resolution intersects them
          # with a test-owned target. Invalid unrelated links grant no ownership.
          owner="$(kaba_classify_path "$rel" 2>/dev/null)" || continue ;;
        *) continue ;;
      esac
      case "$owner" in test) ;; *) continue ;; esac
      if [[ -L "$path" ]]; then target="$(readlink "$path")" || { result=1; break; }; fi
      hash="$(shasum -a 256 "$path")" || { result=1; break; }
    fi
    hash="${hash%% *}"
    jq -cn --arg path "$rel" --arg sha256 "$hash" --arg target "$target" '{path:$path,sha256:$sha256,symlink:$target}' >> "$entries" || { result=1; break; }
  done < "$paths"
  rm -f "$paths"
  return "$result"
}
kaba_dirty_test_work() {
  local paths path owner
  paths="$(mktemp "${TMPDIR:-/tmp}/kaba-dirty-tests.XXXXXX")"
  kaba_changed_paths dirty > "$paths" || { rm -f "$paths"; return 2; }
  while IFS= read -r -d '' path; do
    owner="$(kaba_classify_path "$path")" || { rm -f "$paths"; return 2; }
    case "$owner" in test) rm -f "$paths"; return 0 ;; esac
  done < "$paths"
  rm -f "$paths"
  return 1
}
kaba_validate_scaffolds() {
  local records="$1" feature="$2" row path hash owner
  jq -e 'type=="array" and all(.[]; (.path|type)=="string" and (.sha256|test("^[a-f0-9]{64}$")) and (.package|type)=="string") and ([.[].path]|length)==([.[].path]|unique|length)' "$records" >/dev/null || kaba_die 'invalid scaffold manifest records'
  while IFS= read -r row; do
    path="$(printf '%s' "$row" | jq -r .path)"
    case "$path" in /*|*../*|../*|*/..|..|./*|*//*|*$'\n'*|*$'\r'*|*$'\t'*) kaba_die 'unsafe scaffold manifest path' ;; esac
    case "$path" in */testdata/kaba/"$feature"/*.go|testdata/kaba/"$feature"/*.go) ;; *) kaba_die 'scaffold path is not linked to feature' ;; esac
    owner="$(kaba_classify_path "$path")" || kaba_die 'unsafe scaffold path'
    [[ "$owner" == test ]] || kaba_die 'scaffold path is not test-owned'
    [[ -f "$KABA_REPO_ROOT/$path" && ! -L "$KABA_REPO_ROOT/$path" ]] || kaba_die 'scaffold missing or symlinked'
    hash="$(shasum -a 256 "$KABA_REPO_ROOT/$path")" || return 1
    [[ "${hash%% *}" == "$(printf '%s' "$row" | jq -r .sha256)" ]] || kaba_die 'scaffold content hash mismatch'
  done < <(jq -c '.[]' "$records")
}
