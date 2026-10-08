# Reusable Go Support Implementation Plan

> For agentic workers: read the design and this plan before execution.
> Use the executing-plans workflow for inline execution. Delegate only under applicable
> user or repository authorization. Follow repository Git authorization rules instead
> of any skill instruction to commit automatically.

**Goal:** Add reusable Go support to Kaba with the existing workflow and enforcement
guarantees while preserving Rails/RSpec behavior.

**Architecture:** Keep the shell entry points and workflow gates. Introduce one shared
permission classifier and runner adapters for Go and RSpec. The Go adapter owns Go
discovery, result conversion, digests, compilation scaffolding, and source-aware cleanup.

**Tech stack:** Bash 3.2-compatible scripts, git, jq; Ruby 3.3+ with Prism for RSpec;
Go standard-library tooling for Go analysis and execution.

**Spec:** [Go support design](go-support-design.md).

**Branches:** Work on `feat/go-support`, based on `feat/codex-compatibility-spike`
at `ee8cc1a4576906a06faadedd459a50bb0d4322d0`. This base includes the Codex packaging,
skill metadata, and hooks needed by the adaptation.

## Global constraints

- Follow `AGENTS.md`. Commit, push, PR creation, and merge require separate authorization.
- Preserve `docs/codex-release-readiness.md` and every unrelated change. Record their
  state before implementation so the final review can verify they were preserved.
- Keep changes confined to Kaba and use self-contained test fixtures.
- Keep workflow stages and planned test transitions. Leave clarification loops and
  unrelated workflow/release defects to the user.
- Implement the two-list permissions and missing-declaration scaffold scope.
- Explain a consequential deviation before implementing it. Do not silently weaken a gate,
  add a toolchain dependency to the other adapter, or broaden scaffolding into real behavior.
- Use the existing shell test harness. Every changed/new script needs behavior tests.
- Keep `bash test/run.sh` as the complete suite entry point, including Go helper tests.
- Use failing regression tests first, then minimal implementation and focused verification.
- Preserve existing assertions unless the specified adaptation intentionally changes the
  contract. Do not weaken assertions to obtain a green suite.
- Final compatibility evidence requires Ruby/Prism and Go tests to actually run. Report
  skipped tests and exact tool versions; skips are not proof of compatibility.

## Review focus

1. Colocated production/test files, future files, symlink targets, and moves across
   ownership boundaries must classify consistently in hooks and gates (tasks 1–2).
2. Successful package exit or failed parent setup must not conceal unexecuted cases;
   package failures must not masquerade as individual red tests (tasks 3–4).
3. Table-row additions must preserve sibling identities/digests while changed data or
   shared bodies remain visible; fixtures/helpers need independent protection (tasks 4, 6).
4. Temporary declarations must not replace existing function behavior, alter the real
   source tree, justify synthetic PINs, or leak into implementation validation (task 5).
5. Cleanup must preserve unrelated source and recover exact contents when verification
   fails; Rails configuration, snapshots, and cleanup must retain their behavior (tasks 1, 3, 6–7).

## File structure and interfaces

Keep changes near the existing components. New paths below are planned files, not files
already implemented. Internal Go files may be split by responsibility without changing
the public shell contracts.

| Path | Responsibility |
|---|---|
| `scripts/config.sh` | Load legacy and explicit-runner configuration; validate permission lists |
| `scripts/path-permissions.sh` (new) | Normalize/classify paths; expose the shared permission policy |
| `scripts/session-lock.sh`, `scripts/session-lock-guard.sh`, `scripts/hooks/pre-commit` | Consume the classifier at existing enforcement boundaries |
| `scripts/test-runner.sh` (new) | Select adapter and expose discovery/run/digest/cleanup operations |
| `scripts/adapters/rspec.sh` (new) | Existing RSpec invocation and Ruby helper integration |
| `scripts/adapters/go.sh` (new) | Go invocation, temporary-build lifetime, and helper integration |
| `scripts/go/` (new) | Focused Go parsing, inventory, result, digest, scaffold, and cleanup helpers plus unit tests |
| `scripts/snapshot-tests.sh` | Preserve workflow comparisons; consume adapter data and protected file inventory |
| `scripts/cleanup-tests.sh` | Coordinate source-aware deletions, scaffold cleanup, verification, and rollback |
| `scripts/banned-patterns.sh` | Select applicable test-quality checks for the configured runner |
| `scripts/init-project.sh` | Write confirmed runner/pattern settings and existing hook wiring |
| `test/*_test.sh`, `test/fixtures/` | Existing shell harness plus isolated fixtures and Go integration coverage |

Proposed shell boundaries to establish with tests before wiring callers:

```text
path-permissions.sh classify <repo-relative-or-absolute-path>
  stdout: test | implement | shared | none
  exit: 0 for a valid classification; nonzero for invalid input/configuration

session-lock.sh check <path>...
  retain the current public allow/deny contract and diagnostics

test-runner.sh identities
test-runner.sh run
test-runner.sh digests
  structured output; runner-specific diagnostics on stderr

snapshot-tests.sh capture|compare|identities|validate-plan|allowlist-append
cleanup-tests.sh
  retain the established public workflow entry points
```

Adapter records retain the common identity, description, file, source location, result,
and digest concepts. Expose group relationships explicitly rather than embedding RSpec
address syntax in common comparisons. Add runner/schema/context identification and a
protected-file inventory to Go snapshots; preserve the legacy RSpec reader. Final JSON
field details must be pinned by fixture tests before consumers are switched to them.

## Test commands

The existing `test/run.sh` sources each test file in a separate process and checks its
reported assertion counters. Focused verification must also check those counters:

```bash
bash -c '
  . "$1" || exit 1
  [ "$KABA_TEST_FAIL" -eq 0 ]
' _ test/session_lock_test.sh
```

Use that invocation with each named test file below. Run the complete suite with:

```bash
bash test/run.sh
```

Go helper unit tests must have a `test/go_helpers_test.sh` wrapper that reports a failed
Go test invocation through `test/assert.sh`. Public script tests invoke real scripts in
disposable consumer repositories, not helper internals alone. Test fixture commits are
isolated test setup; they never authorize committing the Kaba task branch.

## Task 1 — Configuration and common permissions

**Files:** modify `scripts/config.sh`, `test/config_test.sh`; create
`scripts/path-permissions.sh`, `test/path_permissions_test.sh`, and
`test/fixtures/go-config.yml` using the configuration in the design.

**Consumes:** legacy settings and the four explicit permission lists.
**Produces:** the classifier contract above and validated configuration for later tasks.

- [ ] Add failing loader tests for the Go example, quoted block/inline lists, empty
  exclusions, missing runner or allow lists, malformed patterns, and ambiguous mixtures
  of legacy and new permission settings. Preserve existing legacy error behavior.
- [ ] Add classifier fixtures for root/nested `*_test.go`, testdata, shared helpers,
  production files, shared dependencies, workflow artifacts, and paths allowed by neither.
  Include paths that do not exist yet and literal special characters in legacy carve-outs.
- [ ] Pin inclusion/exclusion precedence and effective shared ownership, for example:

  ```bash
  classify() { (cd "$repo" && "$PERMISSIONS" classify "$1"); }
  assert_stdout_match "colocated test belongs to tests" '^test$' classify internal/pay/pay_test.go
  assert_stdout_match "production belongs to implementation" '^implement$' classify internal/pay/pay.go
  assert_stdout_match "dependency manifest is shared" '^shared$' classify go.mod
  assert_stdout_match "future fixture is test-owned" '^test$' classify new/package/testdata/input.json
  ```

  Define `PERMISSIONS` as the absolute new script path and construct `repo` using the
  existing `mktemp`/`git init` fixture style. Assertions are examples to add to that fixture.
- [ ] Run the focused tests and confirm the missing behavior causes failures.
- [ ] Implement parsing, legacy translation, normalization, and classification once.
  The matcher uses only documented shared dependencies; expose a required dependency
  change before adopting one. Keep includes/excludes independent of `.gitignore`.
- [ ] Run both new test files and `test/config_test.sh`; all assertions pass.

## Task 2 — Use classification at every ownership boundary

**Files:** modify `scripts/session-lock.sh`, `scripts/session-lock-guard.sh`,
`scripts/hooks/pre-commit`, `test/session_lock_test.sh`, and
`test/session_lock_guard_test.sh`; add `test/ownership_gates_test.sh`.

**Consumes:** task 1 classifier. **Produces:** consistent edit/commit/change-set checks
for later snapshot and end-gate integration.

- [ ] Add failing tests for both session modes against the same colocated files.
  Retain off-mode behavior and both hosts' existing hook formats.
- [ ] Exercise add, update, delete, and move tool payloads, plus actual staged additions,
  deletions, and renames in disposable Git repositories. Check both sides of each move.
- [ ] Add path tests for spaces, repeated `./`, duplicate separators, physical/symlink
  aliases, symlink targets, nonexistent leaves, outside paths, and traversal. Preserve
  paths losslessly through Git change-set plumbing or reject unsupported forms explicitly.
- [ ] Pin the critical negative behavior at the public entry point:

  ```bash
  lock set implement
  assert_fail "implementation cannot write a colocated test" 1 lock check internal/pay/pay_test.go
  assert_fail "implementation cannot remove a fixture" 1 lock check internal/pay/testdata/input.json
  lock set test
  assert_fail "test session cannot write production" 1 lock check internal/pay/pay.go
  ```

  Extend the existing test's `lock` fixture rather than inventing another assertion harness.
- [ ] Confirm failures, replace duplicated ownership logic with the common classifier,
  and run the focused tests plus existing session-start rewiring tests.
- [ ] Verify dirty-state inventory includes staged, unstaged, and untracked files for
  snapshot resume and end-gate consumers, including old paths of deleted files.

## Task 3 — Adapter boundary and Go execution results

**Files:** create `scripts/test-runner.sh`, `scripts/adapters/rspec.sh`,
`scripts/adapters/go.sh`, Go result handling under `scripts/go/`,
`test/runner_adapter_test.sh`, `test/go_results_test.sh`, and Go JSON fixtures;
modify `scripts/snapshot-tests.sh` and affected snapshot tests.

**Consumes:** validated runner/command settings. **Produces:** runner-neutral results
and explicit invalid-run errors; existing RSpec outputs retain their interpretation.

- [ ] Add regression tests before extracting RSpec invocation. Cover normal results,
  dry-run discovery, load errors, missing tools, and supported legacy snapshots/plans.
- [ ] Add Go JSON fixtures for pass/fail/skip, package/build failure, interleaved parallel
  events, malformed/truncated output, unexplained package failure, and early successful exit.
- [ ] Add real temporary Go packages that reproduce the experiment's incomplete runs:

  ```go
  func TestMain(m *testing.M) { os.Exit(0) }
  func TestNever(t *testing.T) { t.Fatal("must execute") }
  ```

  Import `os` and `testing` in that fixture. Assert capture fails because `TestNever`
  did not execute even though the process exited successfully. Add a separate fixture
  where `TestMain` exits nonzero and one where compilation fails before any test runs.
- [ ] Run failing tests, extract the RSpec adapter with no semantic redesign, and add Go
  event conversion. Distinguish structural run errors from valid individual red results.
- [ ] Verify uncached execution and consistent package/build selection; reject command
  options that would silently narrow the inventory used by the workflow gates.
- [ ] Run focused adapter tests and all existing snapshot capture/comparison tests.

## Task 4 — Go discovery and structural digests

**Files:** add focused Go parser/discovery/digest files and unit tests under `scripts/go/`;
add `test/go_helpers_test.sh`, `test/go_discovery_test.sh`, and `test/go_digest_test.sh`;
add source fixtures under `test/fixtures/go/`.

**Consumes:** source tree and runner selection context. **Produces:** expected identities,
group relationships, source locations, supported cleanup locations, and case digests.

- [ ] Add failing fixtures for same-package/external tests, literal named subtests,
  supported named tables, nested cases, duplicates, name normalization collisions,
  unsupported dynamic case generation, and parent setup failing before child registration.
- [ ] Use the agreed table form as a fixture, including independently named outcomes:

  ```go
  for _, tc := range []struct {
      name string
      input int
  }{{"one", 1}, {"two", 2}} {
      t.Run(tc.name, func(t *testing.T) {
          if got := Pay(tc.input); got != tc.input { t.Errorf("got %d", got) }
      })
  }
  ```

- [ ] Confirm discovery failures before implementing AST-based source enumeration.
  Document the accepted table forms and reject forms whose cases cannot be enumerated.
- [ ] Add paired digest fixtures: formatting/comments only; changed assertion; changed
  single-row data; added/reordered row; changed shared setup/body; compiler directives.
  Assert unaffected sibling identities and digests stay equal while affected cases change.
- [ ] Implement source-aware digest composition and match runtime names to the expected
  inventory. Preserve the source-to-case mapping required for precise cleanup.
- [ ] Run Go helper unit tests through the shell wrapper and both public helper test files.

## Task 5 — Validated temporary compilation scaffolding

**Files:** add scaffold validation/build support under `scripts/go/`; modify
`scripts/adapters/go.sh`; add `test/go_scaffold_test.sh` and scaffold fixtures.

**Consumes:** agent-authored test support and expected source inventory.
**Produces:** a validated temporary overlay with deterministic lifetime and unchanged
production files. Existing implementation bodies are preserved.

- [ ] Turn experiment cases into failing script-level tests: missing new type/function,
  new method on existing type, field addition, duplicate declaration, arbitrary production
  replacement, zero-value accidental pass, panic/incomplete run, and stale-overlay collision.
- [ ] Hash production files before/after capture and test-owned files before/after the
  simulated implementation. Assert equality where ownership requires immutability.
- [ ] Enumerate and test accepted declaration/minimal-body AST forms before implementing
  the validator. Reject bodies introducing business behavior or modifying existing bodies.
  Generate existing-type field additions in scripts rather than trusting whole-file replacements.
- [ ] Implement temporary-build creation/cleanup and verify cleanup after successful and
  failed invocations. Exercise supported interruption/error paths and report any recovery gap.
- [ ] Verify missing declarations produce real red results, not synthesized failures.
  A placeholder-induced pass remains subject to the existing PIN requirements; scaffolding
  alone must not establish that real behavior already conforms.
- [ ] Create the real implementation in the disposable fixture, run the same locked tests
  without an overlay, and require green. Assert scaffold/test sources were unchanged.
- [ ] Run focused scaffold, result, and discovery tests together.

## Task 6 — Snapshot protection and exact cleanup

**Files:** modify `scripts/snapshot-tests.sh`, `scripts/cleanup-tests.sh`, and snapshot tests;
add Go cleanup support under `scripts/go/`, `test/go_snapshot_test.sh`,
`test/go_cleanup_test.sh`, and `test/cleanup_tests_test.sh` for the legacy path.

**Consumes:** classifier, complete adapter results, structural digests, and source mappings.
**Produces:** protected-file snapshot comparisons and scripted deletion/verification/rollback.

- [ ] Add failing tests for test-owned helper, fixture, scaffold, and test-source changes,
  including additions/deletions/renames with unchanged individual test outcomes.
- [ ] Test resume detection using classified files instead of a single directory. Preserve
  normal planned test-session modifications and all existing MODIFY/REMOVE/PIN/TOUCH rules.
- [ ] Test format/runner/context mismatches and exact group boundaries. Preserve the
  old RSpec reader; never reinterpret RSpec addresses as Go names.
- [ ] Add exact-removal fixtures: a standalone skipped function; one skipped row with two
  unremoved neighbors; an ambiguous/dynamic source form that must be refused. Verify that
  the expected named case reports skipped before cleanup and only that source unit is deleted.
- [ ] Exercise lock-on, incomplete feature, dirty tree, incorrect remaining test count,
  failed real-suite verification, and successful cleanup. Test scaffolds using a feature's
  generated inventory; ownership itself continues to use patterns, not that inventory.
- [ ] Assert restoration byte-for-byte on failure, for example:

  ```bash
  before="$(git hash-object "$scaffold")"
  assert_fail "cleanup rejects a failed verification run" 1 cleanup
  assert_eq "cleanup restores exact scaffold bytes" "$before" "$(git hash-object "$scaffold")"
  ```

  Define `scaffold` and `cleanup` in the disposable fixture; include unrelated files and
  assert they are unchanged after both success and failure.
- [ ] Implement inventory capture/comparison, exact AST deletion, and coordinated cleanup.
  The script checks completion and lock state, selects recorded scaffold files, verifies
  without overlays, and restores on failure. No LLM-selected deletion or manual rollback.
- [ ] Run new Go tests, legacy cleanup tests, and all existing snapshot/Prism tests.

## Task 7 — Initialization, skills, documentation, and full verification

**Files:** modify `scripts/init-project.sh`, `scripts/banned-patterns.sh`, affected
`skills/*/SKILL.md`, `templates/test-plan-template.md`, affected related templates,
`README.md`, `docs/workflow.md`, `.claude-plugin/plugin.json`,
`.claude-plugin/marketplace.json`, `.codex-plugin/plugin.json`, and relevant tests.
Add `test/go_workflow_test.sh` and a Go quality-check test file. Update `CHANGELOG.md`
only with the implemented user-visible capability and migration/dependency requirements.

- [ ] Add failing initialization tests for explicit Go settings, config round-trip,
  shared file patterns, confirmation/overwrite behavior, and unchanged legacy Rails setup.
- [ ] Add quality-gate tests proving Go files are actually inspected and a failing
  project verification command blocks completion. Preserve applicable documented test
  quality requirements without inventing bans on valid Testify assertions, fakes, local
  HTTP stubs, or fixtures. Unsupported rule translation must be surfaced, not silently skipped.
- [ ] Implement initialization/quality dispatch and update every affected skill reference
  to test-directory-only ownership, RSpec identity syntax, Ruby-only parsing, lazy unresolved
  symbols, criterion comments, and cleanup. Preserve their existing stage responsibilities.
- [ ] Extend manifest/skill tests to verify packaged Go helpers and consistent instructions.
  Documentation must describe actual tested behavior and supported source forms.
- [ ] Run a real Go fixture through initialization, baseline, planned test work, overlay
  post-test capture/compare, locked implementation, real post-implementation capture/compare,
  the configured quality command, and between-feature cleanup. Include a negative attempt
  to edit a test-owned file through each enforcement boundary.
- [ ] Run equivalent legacy compatibility checks with Ruby/Prism available. Ensure Go helper
  tests run through `bash test/run.sh`, then run the complete suite under Bash 3.2.
- [ ] Record exact Go/Ruby/Prism versions and test outcomes. Base supported-version claims
  on executed compatibility tests, not on the disposable experiment alone. Exercise
  assertion-library and project-command integration using self-contained fixtures that
  require no external service credentials. Report untested platform/build-context limits.
- [ ] Run `git diff --check`, review the full task diff, and verify unrelated changes
  against their recorded pre-implementation state. Finish with actual results and material limitations.

## Completion and authorization boundary

Implementation is complete only when all seven task deliverables and their tests pass,
the full suite has run with both required toolchains, the design has no silent
deviations, and unrelated files remain intact. Keep a checkable record of validation gaps.
Do not convert successful disposable experiments or skipped tests into a completion claim.

Do not commit, push, open a PR, or merge as an implicit final step. Report completion and
follow the user's separate Git authorization under `AGENTS.md`.
