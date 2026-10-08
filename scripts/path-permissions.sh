#!/usr/bin/env bash
# One repository-relative policy for edit guards, change sets and file inventories.
# Source this file and call kaba_classify_path after kaba_load_config, or use the CLI.
_KABA_PERMISSIONS_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_KABA_PERMISSIONS_DIR/config.sh"

_kaba_path_error() { printf 'ERROR: invalid permission path: %s\n' "$*" >&2; return 1; }
_kaba_normalize_path() {
  local p="$1"
  case "$p" in ''|*$'\n'*|*$'\r'*|*$'\t'*) _kaba_path_error "empty path or unsupported control character"; return 1 ;; esac
  case "$p" in *//*) p="$(printf '%s' "$p" | sed 's://*:/:g')" ;; esac
  while [ "${p#./}" != "$p" ]; do p="${p#./}"; done
  case "/$p/" in */../*|*/./*) _kaba_path_error "traversal in '$1'; pass a normalized path"; return 1 ;; esac
  [ "$p" = / ] || p="${p%/}"
  printf '%s' "$p"
}

# Resolve every ancestor and a symlink leaf. Future regular leaves are valid;
# dangling/cyclic links are not. readlink and cd are available on supported hosts.
_kaba_resolve_path() {
  local p="$1" depth="${2:-0}" parent leaf target physical
  [ "$depth" -lt 64 ] || { _kaba_path_error "cyclic or excessively deep symlink '$p'"; return 1; }
  if [ -L "$p" ]; then
    [ -e "$p" ] || { _kaba_path_error "dangling or cyclic symlink '$p'"; return 1; }
    # Disable readlink's delimiter; the sentinel preserves target newlines.
    target="$(readlink -n "$p" && printf '.')" || return 1
    target="${target%.}"
    case "$target" in ''|*$'\n'*|*$'\r'*|*$'\t'*) _kaba_path_error "unsupported control character in symlink target '$p'"; return 1 ;; esac
    case "$target" in /*) ;; *) target="$(dirname "$p")/$target" ;; esac
    _kaba_resolve_path "$target" "$((depth + 1))"
  elif [ -d "$p" ]; then
    physical="$(cd "$p" 2>/dev/null && pwd -P && printf '.')" || { _kaba_path_error "cannot resolve '$p'"; return 1; }
    physical="${physical%.}"; physical="${physical%$'\n'}"
    case "$physical" in *$'\n'*|*$'\r'*|*$'\t'*) _kaba_path_error "unsupported control character in resolved directory '$p'"; return 1 ;; esac
    printf '%s\n' "$physical"
  else
    parent="$(dirname "$p")"; leaf="$(basename "$p")"
    [ "$parent" != "$p" ] || { _kaba_path_error "cannot resolve '$p'"; return 1; }
    parent="$(_kaba_resolve_path "$parent" "$depth")" || return 1
    [ ! -e "$parent" ] || [ -d "$parent" ] || { _kaba_path_error "parent is not a directory '$parent'"; return 1; }
    printf '%s/%s' "${parent%/}" "$leaf"
  fi
}

_kaba_relative_path() {
  local p="$1" physical_root="$2" ancestor tail="" resolved
  case "$p" in
    "$KABA_REPO_ROOT"/*) printf '%s' "${p#"$KABA_REPO_ROOT"/}"; return 0 ;;
    "$physical_root"/*) printf '%s' "${p#"$physical_root"/}"; return 0 ;;
    /*)
      # Absolute root aliases (e.g. /var and /private/var on macOS) preserve
      # the lexical tail once an ancestor identifies the repository root.
      ancestor="$p"
      while [ "$ancestor" != / ]; do
        if [ -d "$ancestor" ]; then
          resolved="$(cd "$ancestor" 2>/dev/null && pwd -P)" || return 1
          if [ "$resolved" = "$physical_root" ] && [ -n "$tail" ]; then printf '%s' "$tail"; return 0; fi
        fi
        tail="$(basename "$ancestor")${tail:+/$tail}"
        ancestor="$(dirname "$ancestor")"
      done
      _kaba_path_error "outside repository '$p'"; return 1 ;;
    *) printf '%s' "$p" ;;
  esac
}

_kaba_classify_relative() {
  KABA_MATCH_PATH="$1" awk '
    function regex(p,    parts,n,i,s,c,j,r) {
      n=split(p,parts,"/"); r="^"
      for(i=1;i<=n;i++) {
        s=parts[i]
        if(s=="**") { if(i<n) r=r "([^/]+/)*"; else r=r ".*"; continue }
        for(j=1;j<=length(s);j++) {
          c=substr(s,j,1)
          if(c=="*") r=r "[^/]*"
          else { if(index("\\.^$+()|[]{}?",c)) r=r "\\"; r=r c }
        }
        if(i<n) r=r "/"
      }
      return r "$"
    }
    function matches(list,path,literal,    a,n,i,p,base) {
      n=split(list,a,"\n")
      for(i=1;i<=n;i++) {
        p=a[i]; if(p=="") continue
        if(literal) {
          if(substr(p,length(p),1)=="/") {
            if(index(path,p)==1) return 1
          } else if(path==p) return 1
        } else if(substr(p,length(p),1)=="/") {
          base=substr(p,1,length(p)-1)
          if(path ~ regex(base) || path ~ regex(p "**")) return 1
        } else {
          # A subtree includes its directory entry too (not only children).
          # Symlink targets are classified at that entry before descendants.
          if(substr(p,length(p)-2)=="/**" && path ~ regex(substr(p,1,length(p)-3))) return 1
          if(path ~ regex(p)) return 1
        }
      }
      return 0
    }
    BEGIN {
      p=ENVIRON["KABA_MATCH_PATH"]; legacy=ENVIRON["KABA_PERMISSION_MODE"]=="legacy"
      t=matches(ENVIRON["KABA_TEST_WRITE_ALLOW"],p,legacy) && !matches(ENVIRON["KABA_TEST_WRITE_EXCLUDE"],p,legacy)
      # Legacy implementation allows everything outside the literal test subtree.
      if(legacy) impl=!matches(ENVIRON["KABA_IMPLEMENT_WRITE_EXCLUDE"],p,1)
      else impl=matches(ENVIRON["KABA_IMPLEMENT_WRITE_ALLOW"],p,0) && !matches(ENVIRON["KABA_IMPLEMENT_WRITE_EXCLUDE"],p,0)
      if(t && impl) print "shared"; else if(t) print "test"; else if(impl) print "implement"; else print "none"
    }
  '
}

kaba_classify_path() {
  local p physical_root relative resolved lexical_class resolved_class t=0 impl=0
  [ "$#" -eq 1 ] || { _kaba_path_error "classify requires exactly one path"; return 1; }
  p="$(_kaba_normalize_path "$1")" || return 1
  physical_root="$(cd "$KABA_REPO_ROOT" && pwd -P)" || return 1
  relative="$(_kaba_relative_path "$p" "$physical_root")" || return 1
  [ -n "$relative" ] || { _kaba_path_error "repository root is not a file path"; return 1; }
  resolved="$(_kaba_resolve_path "$physical_root/$relative")" || return 1
  case "$resolved" in
    "$physical_root"/*) resolved="${resolved#"$physical_root"/}" ;;
    *) _kaba_path_error "resolved target outside repository '$1'"; return 1 ;;
  esac
  lexical_class="$(_kaba_classify_relative "$relative")" || return 1
  resolved_class="$(_kaba_classify_relative "$resolved")" || return 1
  case "$lexical_class:$resolved_class" in test:test|test:shared|shared:test|shared:shared) t=1 ;; esac
  case "$lexical_class:$resolved_class" in implement:implement|implement:shared|shared:implement|shared:shared) impl=1 ;; esac
  if [ "$t" -eq 1 ] && [ "$impl" -eq 1 ]; then printf 'shared\n'
  elif [ "$t" -eq 1 ]; then printf 'test\n'
  elif [ "$impl" -eq 1 ]; then printf 'implement\n'
  else printf 'none\n'; fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    classify) shift; kaba_load_config; kaba_classify_path "$@" ;;
    *) printf 'Usage: path-permissions.sh classify <path>\n' >&2; exit 1 ;;
  esac
fi
