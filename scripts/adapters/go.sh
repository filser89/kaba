#!/usr/bin/env bash
# Standard Go commands run against a complete, source-discovered test inventory.
kaba_go_parse_command() {
  local token value effective_flags
  KABA_GO_ARGS=()
  KABA_GO_PACKAGES=()
  KABA_GO_BUILD_ARGS=()
  KABA_GO_TAGS=""
  case "$KABA_TEST_COMMAND" in *\'*|*\"*|*\;*|*\|*|*\&*|*\$*|*\`*) kaba_die 'Go test_command supports plain go test arguments, not shell wrappers/quoting' ;; esac
  read -r -a KABA_GO_ARGS <<< "$KABA_TEST_COMMAND"
  [[ ${#KABA_GO_ARGS[@]} -ge 2 && "${KABA_GO_ARGS[1]}" == test ]] || kaba_die 'Go test_command must be go test with explicit package selection'
  KABA_GO_BIN="${KABA_GO_ARGS[0]}"
  case "$KABA_GO_BIN" in go|*/go) ;; *) kaba_die 'Go test_command wrappers are not supported; configure go test directly' ;; esac
  KABA_GO_BIN="$(cd "$KABA_REPO_ROOT" && command -v "$KABA_GO_BIN")" || kaba_die 'go not found (required for Go test execution)'
  case "$KABA_GO_BIN" in /*) ;; *) KABA_GO_BIN="$KABA_REPO_ROOT/$KABA_GO_BIN" ;; esac
  [[ -z "${GOFLAGS:-}" ]] || kaba_die 'GOFLAGS is not supported for snapshots; configure supported flags in test_command (user overlays are forbidden)'
  effective_flags="$(cd "$KABA_REPO_ROOT" && "$KABA_GO_BIN" env GOFLAGS)" || kaba_die 'Go build flags could not be read'
  [[ -z "$effective_flags" ]] || kaba_die 'GOFLAGS is not supported for snapshots; configure supported flags in test_command (user overlays are forbidden)'
  local i=2
  while [[ "$i" -lt ${#KABA_GO_ARGS[@]} ]]; do
    token="${KABA_GO_ARGS[$i]}"
    case "$token" in
      -tags|-timeout|-parallel|-p)
        i=$((i+1)); [[ "$i" -lt ${#KABA_GO_ARGS[@]} ]] || kaba_die "$token needs a value"
        value="${KABA_GO_ARGS[$i]}"
        [[ "$value" != -* ]] || kaba_die "$token needs a value"
        if [[ "$token" == -tags ]]; then KABA_GO_TAGS="$value"; fi ;;
      -tags=*) KABA_GO_TAGS="${token#-tags=}" ;;
      -timeout=*|-parallel=*|-p=*|-v|-short|-cover) ;;
      -*) kaba_die "unsupported Go test option $token; options narrowing inventory, cached counts, and user overlays are forbidden" ;;
      *) KABA_GO_PACKAGES+=("$token") ;;
    esac
    i=$((i+1))
  done
  [[ ${#KABA_GO_PACKAGES[@]} -gt 0 ]] || KABA_GO_PACKAGES=(.)
}

kaba_go_helper() {
  (cd "$SCRIPT_DIR/go" && "$KABA_GO_BIN" run . "$@")
}

# The caller owns temporary-file cleanup; only post-test invokes this hook.
. "$SCRIPT_DIR/adapters/go-scaffold.sh"

kaba_go_operation() {
  local operation="$1" phase="$2" package_selection context process_exit
  kaba_go_parse_command
  KABA_GO_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/kaba-go-run.XXXXXX")"
  KABA_GO_OVERLAY=""
  KABA_GO_SCAFFOLD_JSON='{"overlay":null,"files":[],"packages":[]}'
  if [[ "$phase" == post-test ]]; then kaba_go_prepare_scaffold; fi
  package_selection="${KABA_GO_PACKAGES[*]}"
  local helper_args=(identities --include-source-files --root "$KABA_REPO_ROOT" --packages "$package_selection" --go-bin "$KABA_GO_BIN" --permission-helper "$SCRIPT_DIR/path-permissions.sh")
  [[ -z "$KABA_GO_TAGS" ]] || helper_args+=(--tags "$KABA_GO_TAGS")
  [[ -z "$KABA_GO_OVERLAY" ]] || helper_args+=(--overlay "$KABA_GO_OVERLAY")
  kaba_go_helper "${helper_args[@]}" > "$KABA_GO_TMPDIR/source.json" || kaba_die 'Go source inventory discovery failed'
  jq '.records' "$KABA_GO_TMPDIR/source.json" > "$KABA_GO_TMPDIR/inventory.json"
  context="$(cd "$KABA_REPO_ROOT" && "$KABA_GO_BIN" env -json)" || kaba_die 'Go build context could not be read'
  # Select effective compiler/build settings, excluding volatile caches and generated GOGCCFLAGS.
  context="$(printf '%s' "$context" | jq 'with_entries(select(.key | test("^(GOOS|GOARCH|GOVERSION|GOWORK|GOEXPERIMENT|GOAMD64|GO386|GOARM|GOARM64|GOMIPS|GOMIPS64|GOPPC64|GORISCV64|GOWASM|GOFIPS140|GODEBUG|CGO_ENABLED|CGO_CFLAGS|CGO_CPPFLAGS|CGO_CXXFLAGS|CGO_FFLAGS|CGO_LDFLAGS|CC|CXX|AR|FC|PKG_CONFIG)$")))')"
  context="$(printf '%s' "$context" | jq --arg command "$KABA_TEST_COMMAND" --arg packages "$package_selection" --arg tags "$KABA_GO_TAGS" '. + {command:$command,packages:$packages,tags:$tags,count:1}')"
  if [[ "$operation" == run ]]; then
    local run_args=("${KABA_GO_ARGS[@]:1}" -json -count=1)
    [[ -z "$KABA_GO_OVERLAY" ]] || run_args+=(-overlay "$KABA_GO_OVERLAY")
    process_exit=0
    (cd "$KABA_REPO_ROOT" && "$KABA_GO_BIN" "${run_args[@]}") > "$KABA_GO_TMPDIR/events.jsonl" || process_exit=$?
    bash "$SCRIPT_DIR/adapters/go-results.sh" "$KABA_GO_TMPDIR/inventory.json" "$KABA_GO_TMPDIR/events.jsonl" "$process_exit" > "$KABA_GO_TMPDIR/result.json" || return 1
  else
    jq '{examples:[.[] | select(.is_group != true)],groups:[.[] | select(.is_group == true)]}' "$KABA_GO_TMPDIR/inventory.json" > "$KABA_GO_TMPDIR/result.json"
  fi
  jq --slurpfile source "$KABA_GO_TMPDIR/source.json" --argjson context "$context" --argjson scaffolds "$KABA_GO_SCAFFOLD_JSON" '. + {runner:"go",schema:1,context:$context,source_files:$source[0].source_files,overlay_packages:$scaffolds.packages,scaffolds:$scaffolds.files}' "$KABA_GO_TMPDIR/result.json"
}
