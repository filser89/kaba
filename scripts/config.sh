#!/usr/bin/env bash
# Shared explicit configuration; sourced by Kaba's shell entry points.
kaba_die() { echo "ERROR: $*" >&2; exit 1; }
kaba_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null \
    || kaba_die "not inside a git repository — kaba requires git for its enforcement gates"
}

# Parse the flat scalar/list YAML subset used by Kaba. Quotes protect comments and
# inline-list commas; unsupported YAML forms fail instead of becoming permissions.
_kaba_yaml_read() {
  awk -v key="$1" -v mode="$3" '
    function fail(message) { print "ERROR: " key ": " message > "/dev/stderr"; failed=1; exit 1 }
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function uncomment(s,    i,c,q,out) {
      q=""; out=""
      for(i=1;i<=length(s);i++) {
        c=substr(s,i,1)
        if(q != "") {
          out=out c
          if(c==q) {
            if(q=="\047" && substr(s,i+1,1)==q) { out=out q; i++ }
            else q=""
          } else if(q=="\042" && c=="\\") { out=out substr(s,++i,1) }
        } else {
          if(c=="#" && (i==1 || substr(s,i-1,1) ~ /[ \t]/)) break
          out=out c
          if(c=="\047" || c=="\042") q=c
        }
      }
      if(q!="") fail("unterminated YAML quote")
      return trim(out)
    }
    function value(s,    q,i,c,out) {
      s=trim(s); q=substr(s,1,1)
      if(q=="\047" || q=="\042") {
        if(substr(s,length(s),1)!=q || length(s)<2) fail("malformed quoted value")
        s=substr(s,2,length(s)-2); out=""
        for(i=1;i<=length(s);i++) {
          c=substr(s,i,1)
          if(c==q) {
            if(q=="\047" && substr(s,i+1,1)==q) { i++; out=out q }
            else fail("unexpected quote in value")
          } else if(q=="\042" && c=="\\") {
            c=substr(s,++i,1)
            if(c!="\\" && c!="\042") fail("unsupported YAML escape")
            out=out c
          } else out=out c
        }
        return out
      }
      if(s ~ /^[&*!{|>]/) fail("unsupported YAML value; quote literal text")
      if(s ~ /:[ \t]/) fail("unsupported YAML mapping; quote literal colons")
      return s
    }
    function emit(s,    v) { v=value(s); if(v=="") fail("empty list entry"); print v }
    function inline(s,    i,c,q,item) {
      if(substr(s,length(s),1)!="]") fail("malformed inline list")
      s=substr(s,2,length(s)-2); if(trim(s)=="") return
      q=""; item=""
      for(i=1;i<=length(s);i++) {
        c=substr(s,i,1)
        if(q!="") {
          item=item c
          if(c==q) {
            if(q=="\047" && substr(s,i+1,1)==q) { item=item q; i++ }
            else q=""
          } else if(q=="\042" && c=="\\") item=item substr(s,++i,1)
        } else if(c==",") { emit(item); item="" }
        else { item=item c; if(c=="\047" || c=="\042") q=c }
      }
      if(q!="") fail("unterminated YAML quote")
      emit(item)
    }
    $0 ~ "^" key ":[ \t]*" {
      if(found) fail("duplicate key")
      found=1; s=$0; sub("^" key ":[ \t]*", "", s); s=uncomment(s)
      if(mode=="scalar") { print value(s); active=0 }
      else if(substr(s,1,1)=="[") { inline(s); active=0 }
      else if(s=="") active=1
      else if(mode=="strictlist") fail("expected a block list or inline list")
      else { emit(s); active=0 }
      next
    }
    active {
      s=uncomment($0); if(s=="") next
      if($0 ~ /^[^ \t]/ && s !~ /^-/) { active=0; next }
      if(s !~ /^-[ \t]+/) fail("expected a block list entry")
      sub(/^-[ \t]+/, "", s); emit(s)
    }
    END { if(failed) exit 1 }
  ' "$2"
}
_kaba_yaml_scalar() { _kaba_yaml_read "$1" "$2" scalar; }
_kaba_yaml_list() { _kaba_yaml_read "$1" "$2" "${3:-list}"; }
_kaba_yaml_has() { grep -Eq "^$1:" "$2"; }
_kaba_slash() { case "$1" in */) printf '%s' "$1" ;; *) printf '%s/' "$1" ;; esac; }

# Explicit patterns use only * and whole-segment **. Legacy carve-outs stay literal.
_kaba_normalize_pattern() {
  local p="$1" segment rest
  while [ "${p#./}" != "$p" ]; do p="${p#./}"; done
  case "$p" in *//*) p="$(printf '%s' "$p" | sed 's://*:/:g')" ;; esac
  case "$p" in ''|/*|*'!'*|*'?'*|*'['*|*']'*|*'{'*|*'}'*|*'\'*|*$'\n'*|*$'\r'*|*$'\t'*)
    kaba_die "invalid permission pattern '$1': use repo-relative paths with * or whole-segment **" ;;
  esac
  case "/$p/" in */../*|*/./*) kaba_die "invalid permission pattern '$1': traversal is not allowed" ;; esac
  rest="$p"
  while [ -n "$rest" ]; do
    segment="${rest%%/*}"
    case "$segment" in *\*\**) [ "$segment" = '**' ] || kaba_die "invalid permission pattern '$1': ** must occupy a whole path segment" ;; esac
    case "$rest" in */*) rest="${rest#*/}" ;; *) rest="" ;; esac
  done
  printf '%s\n' "$p"
}
_kaba_permission_list() {
  local values entry result=""
  values="$(_kaba_yaml_list "$1" "$2" strictlist)" || kaba_die "$2: invalid permission list '$1'"
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    entry="$(_kaba_normalize_pattern "$entry")" || return 1
    result="${result}${result:+$'\n'}$entry"
  done <<LIST
$values
LIST
  printf '%s' "$result"
}

kaba_load_config() {
  local root cfg key explicit=0 v
  root="$(kaba_repo_root)" || exit 1
  cfg="$root/.kaba/config.yml"
  [ -f "$cfg" ] || kaba_die "$cfg not found — run /kaba:init"
  KABA_TEST_DIR="$(_kaba_yaml_scalar test_dir "$cfg")" || kaba_die "$cfg: invalid test_dir"
  KABA_TEST_COMMAND="$(_kaba_yaml_scalar test_command "$cfg")" || kaba_die "$cfg: invalid test_command"
  KABA_FEATURE_DIR="$(_kaba_yaml_scalar feature_dir "$cfg")" || kaba_die "$cfg: invalid feature_dir"
  KABA_LINTER_COMMAND="$(_kaba_yaml_scalar linter_command "$cfg")" || kaba_die "$cfg: invalid linter_command"
  KABA_TEST_WRITABLE="$(_kaba_yaml_list test_writable "$cfg")" || kaba_die "$cfg: invalid test_writable"
  KABA_RULES_FILES="$(_kaba_yaml_list rules_files "$cfg")" || kaba_die "$cfg: invalid rules_files"
  KABA_TEST_RUNNER="$(_kaba_yaml_scalar test_runner "$cfg")" || kaba_die "$cfg: invalid test_runner"

  for key in test_write_allow test_write_exclude implement_write_allow implement_write_exclude; do
    if _kaba_yaml_has "$key" "$cfg"; then explicit=1; fi
  done
  KABA_TEST_WRITE_ALLOW="" KABA_TEST_WRITE_EXCLUDE="" KABA_IMPLEMENT_WRITE_ALLOW="" KABA_IMPLEMENT_WRITE_EXCLUDE=""
  if [ "$explicit" -eq 1 ]; then
    if _kaba_yaml_has test_dir "$cfg" || _kaba_yaml_has test_writable "$cfg"; then
      kaba_die "$cfg: cannot mix legacy test_dir/test_writable with explicit permission lists"
    fi
    [ -n "$KABA_TEST_RUNNER" ] || kaba_die "$cfg: required key 'test_runner' is missing or empty for explicit permissions"
    for key in test_write_allow test_write_exclude implement_write_allow implement_write_exclude; do
      _kaba_yaml_has "$key" "$cfg" || kaba_die "$cfg: required key '$key' is missing"
    done
    KABA_TEST_WRITE_ALLOW="$(_kaba_permission_list test_write_allow "$cfg")" || exit 1
    KABA_TEST_WRITE_EXCLUDE="$(_kaba_permission_list test_write_exclude "$cfg")" || exit 1
    KABA_IMPLEMENT_WRITE_ALLOW="$(_kaba_permission_list implement_write_allow "$cfg")" || exit 1
    KABA_IMPLEMENT_WRITE_EXCLUDE="$(_kaba_permission_list implement_write_exclude "$cfg")" || exit 1
    [ -n "$KABA_TEST_WRITE_ALLOW" ] || kaba_die "$cfg: required key 'test_write_allow' is empty"
    [ -n "$KABA_IMPLEMENT_WRITE_ALLOW" ] || kaba_die "$cfg: required key 'implement_write_allow' is empty"
    KABA_PERMISSION_MODE=explicit
  else
    [ -n "$KABA_TEST_DIR" ] || kaba_die "$cfg: required key 'test_dir' is missing or empty"
    KABA_TEST_RUNNER="${KABA_TEST_RUNNER:-rspec}"
    [ "$KABA_TEST_RUNNER" = rspec ] || kaba_die "$cfg: test_runner '$KABA_TEST_RUNNER' requires explicit permission lists"
    KABA_PERMISSION_MODE=legacy
    KABA_TEST_DIR="$(_kaba_slash "$KABA_TEST_DIR")"
  fi
  case "$KABA_TEST_RUNNER" in rspec|go) ;; *) kaba_die "$cfg: unsupported test_runner '$KABA_TEST_RUNNER' (use rspec or go)" ;; esac
  [ -n "$KABA_TEST_COMMAND" ] || kaba_die "$cfg: required key 'test_command' is missing or empty"
  [ -n "$KABA_FEATURE_DIR" ] || kaba_die "$cfg: required key 'feature_dir' is missing or empty"
  [ -n "$KABA_LINTER_COMMAND" ] || kaba_die "$cfg: required key 'linter_command' is missing or empty"
  KABA_FEATURE_DIR="$(_kaba_slash "$KABA_FEATURE_DIR")"
  for v in "$KABA_TEST_DIR" "$KABA_FEATURE_DIR"; do
    case "/$v" in //*|*/../*|*/./*) kaba_die "$cfg: test_dir and feature_dir must be plain repo-relative paths (got '$v')" ;; esac
  done
  if [ "$KABA_PERMISSION_MODE" = legacy ]; then
    case "$KABA_FEATURE_DIR" in "$KABA_TEST_DIR"*) kaba_die "$cfg: feature_dir '$KABA_FEATURE_DIR' is a prefix-path of test_dir '$KABA_TEST_DIR' — they must not overlap" ;; esac
    case "$KABA_TEST_DIR" in "$KABA_FEATURE_DIR"*) kaba_die "$cfg: test_dir '$KABA_TEST_DIR' is a prefix-path of feature_dir '$KABA_FEATURE_DIR' — they must not overlap" ;; esac
    # Consumers distinguish legacy literal entries from explicit wildcard patterns.
    KABA_TEST_WRITE_ALLOW="$KABA_TEST_DIR"$'\n'"$KABA_FEATURE_DIR${KABA_TEST_WRITABLE:+$'\n'$KABA_TEST_WRITABLE}"
    KABA_IMPLEMENT_WRITE_ALLOW='**'
    KABA_IMPLEMENT_WRITE_EXCLUDE="$KABA_TEST_DIR"
  fi
  KABA_REPO_ROOT="$root"
  export KABA_REPO_ROOT KABA_TEST_DIR KABA_TEST_COMMAND KABA_FEATURE_DIR \
    KABA_LINTER_COMMAND KABA_TEST_WRITABLE KABA_RULES_FILES KABA_TEST_RUNNER \
    KABA_PERMISSION_MODE KABA_TEST_WRITE_ALLOW KABA_TEST_WRITE_EXCLUDE \
    KABA_IMPLEMENT_WRITE_ALLOW KABA_IMPLEMENT_WRITE_EXCLUDE
}
