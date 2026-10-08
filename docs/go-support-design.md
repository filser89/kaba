# Reusable Go support — design

Read this with [the implementation plan](go-support-plan.md).

## Scope

- Add reusable Go support inside Kaba while preserving Rails/RSpec support, workflow
  stages, session boundaries, and planned test-state transitions.
- Preserve the unrelated uncommitted `docs/codex-release-readiness.md` change.
- Existing workflow-behavior defects, clarification loops, and unrelated release
  readiness fixes are outside scope. Carry established behavior forward instead of
  reopening its design.

## Reusable Go requirements

Support standard Go testing, colocated test files, testdata fixtures, and configurable
shared-helper locations. Assertion libraries and integration-test infrastructure belong
to the project using Kaba. Project-configured commands can run formatting, static
analysis, vulnerability checks, unit/integration tests, and race detection.

## Explicit session permissions

Projects configure independent allow/exclude pattern lists for the test session and
the implementation session. Within each list, exclusions win regardless of order.
Both sessions can edit a path allowed by both; neither can edit a path allowed by
neither. There is no extra rule rejecting overlaps.

The implementation default is everything except the configured test patterns.
The test session explicitly allows tests, support files, workflow artifacts, and
shared dependency/configuration files. Patterns cover future files automatically;
there are no growing per-file ownership permission lists.

Example configuration for a Go project:

```yaml
test_runner: go
test_command: go test ./...
linter_command: make verify
feature_dir: features/
rules_files: [AGENTS.md]

test_write_allow:
  - "**/*_test.go"
  - "**/testdata/**"
  - "internal/testutil/**"
  - "features/**"
  - "go.mod"
  - "go.sum"
test_write_exclude: []

implement_write_allow:
  - "**"
implement_write_exclude:
  - "**/*_test.go"
  - "**/testdata/**"
  - "internal/testutil/**"
```

`make verify` is an example of a project-owned command, not a new required Makefile
target. The existing configured quality-command gate remains the place to run the
project's aggregate checks.

Pattern rules:

- Match normalized repository-relative paths from the repository root.
- `*` matches within one path segment; `**` spans zero or more directories.
- A trailing `/` means a subtree. Use `**/` explicitly when matching at any depth.
- These are explicit wildcard lists, not full ordered gitignore rules. Do not read
  the project's `.gitignore` as an ownership policy or give `!` ordering semantics.
- Reject malformed or unsupported patterns with an actionable error instead of
  guessing. Treat YAML quotes as quoting, not as part of the pattern.
- Normalize repeated leading `./` and path separators consistently. Reject ambiguous
  traversal and outside-repository targets. Symlinks cannot evade classification.
- Additions check the new path; deletions check the old path; renames check both.
  Include staged, unstaged, and untracked changes in the appropriate gates.

One classifier serves edit guards, commit checks, resume detection, snapshots where
applicable, cleanup, and end gates. Its effective classifications are:

| Test permission | Implementation permission | Classification |
|---|---|---|
| Yes | No | Test-owned |
| No | Yes | Implementation-owned |
| Yes | Yes | Shared |
| No | No | Neither |

The test-owned file set comes from this classifier, not a third configurable list.
Workflow artifacts and shared files retain existing skill-level restrictions.
General artifact-locking and permission-freezing changes are outside scope.

## Adapters and unchanged workflow gates

Keep the current shell entry points. Select a Go or RSpec adapter for discovery,
execution/result conversion, source digests, and source-aware cleanup. The existing
baseline, post-test, post-implementation, plan validation, and planned-change gates
retain their roles. MODIFY, REMOVE, PIN, and TOUCH retain their meanings.

The RSpec adapter retains its JSON execution, dry-run discovery, positional identities,
and Ruby/Prism parsing. The Go adapter uses Go's parser and JSON test events. Shared
operations must not make Rails users install Go or make Go-only users install Prism.
Any additional runtime dependency is a consequential change to surface before adoption.

Go execution must distinguish compilation failure, package-level failure, individual
test failure, skip, and success. Build errors, unexplained package failures, malformed
output, and incomplete result inventories invalidate capture rather than becoming
synthetic failed tests. Snapshot runs bypass cached results and keep package/build
selection consistent throughout the feature. Parent/package summaries are not extra
table-case tests; unaccounted parent/package failures still block validation.

## Go identities, discovery, and source digests

- Use package identity plus the full test/subtest name. Match group boundaries exactly.
- Table cases are individually named `t.Run` subtests with explicit, stable, unique
  names in a supported script-readable source structure.
- The test-writing agent follows that convention; the user does not configure each case.
- Scripts enumerate the expected cases before execution. A failed setup must not erase
  the expected inventory. Reject unsupported dynamic structures explicitly.
- Reordering named cases preserves identities; renaming changes identity.
- Support same-package and external test packages. Detect ambiguous names rather than
  trusting automatically assigned duplicate suffixes.
- Record source locations and formatting-insensitive structural digests. A new table
  row must not change sibling digests; changed row data changes the corresponding case
  digest; changed shared test-body/setup code affects the cases using it.
- Preserve compiler-relevant source information when computing digests; comments that
  affect compilation are not ordinary formatting.

Go snapshots also record the path/content inventory of all test-owned files, including
helpers, fixtures, and scaffolding. Post-test to post-implementation checks protect the
entire set from changes, additions, deletions, and renames. During test writing, normal
planned edits remain possible; do not impose whole-tree immutability across that phase.
The Git end gate remains as an independent check using the same classifier.

## Compilation scaffolding

The purpose is to compile and execute tests before the required production declarations
exist. The test-session agent supplies missing declarations and minimal placeholder
bodies as test support. Scripts validate the scaffolding and assemble a temporary Go
overlay. The real production tree remains unchanged.

Scaffolding may supply missing types, fields, functions, and methods. For a missing
field on an existing type, a script generates a temporary source transformation that
preserves existing function bodies. The agent cannot provide unrestricted replacement
production files. Rewriting existing business behavior is outside the scaffold scope;
compilation problems outside that scope must be reported precisely.

Store scaffold source in configured test-owned support locations, such as a package's
`testdata/kaba/`. Include it in the protected file inventory. Temporary overlay/config
files belong to the runner and are removed after each invocation, including failures.

Actual outcomes must meet the existing gates. A zero/default placeholder can pass a
test accidentally; its existence is not proof of red. A panic can terminate the package
and hide later cases; do not use panic as a blanket strategy for producing red results.
A PIN must represent already-conforming real behavior, not behavior supplied only by
scaffolding. Post-implementation validation uses no scaffolding or overlays.

## Removal and cleanup

Keep the existing skip-now/delete-between-features process. Go uses the removal reason
`REMOVED by <feature>` through `t.Skip`. A table removal skips only its named case.
Source-aware cleanup deletes the exact marked function or table row, never an entire
loop to remove one case. Use the supported source structure to identify the deletion;
ambiguous or unsupported forms fail explicitly.

Extend the existing between-feature cleanup command to remove completed-feature
scaffolding. Scripts perform all four operations: verify completion/lock-off, delete
the recorded files, run the real suite without overlays, and restore exact contents
if verification fails. The LLM invokes the command and reports its result; it does not
choose deletion targets or perform rollback manually. Preserve the established clean
tree and test-count checks for test removal.

Scaffold sources remain protected through implementation. They are removed when the
cleanup command runs, not automatically at implementation completion. Ordinary Go test
execution does not compile Go source inside testdata directories.

## Compatibility and quality

Existing Rails configurations load without migration. Translate legacy `test_dir`,
`feature_dir`, and `test_writable` into equivalent permissions internally. Preserve
legacy exact-path versus subtree carve-out semantics. Existing Rails snapshots and
plans keep their supported interpretation; reject incompatible runner/format/context
comparisons explicitly instead of silently weakening checks.

Initialization proposes and confirms the runner, patterns, shared files, and commands.
Update all affected skills/templates and both plugin packages together. The Go test
quality path must inspect Go files and preserve applicable documented requirements;
running RSpec-only expressions over zero Go files is not a valid quality check.
Ordinary assertions, test doubles, local HTTP stubs, and fixtures must remain usable
under the project's conventions.

## Evidence and limits

A disposable experiment used Go 1.27.0 on darwin/arm64 outside both repositories.
It demonstrated virtual missing declarations, named red cases, unchanged tests turning
green against real implementation without overlays, additive methods, script-generated
field additions, stable names under reordering/parallel execution, and scripted cleanup
with exact restoration after a nonzero verification result.

It also demonstrated build failure without individual results, package success without
any tests running, hidden subtests after failed setup, package abort after panic, and
an accidentally green test against a zero-value placeholder.

The experiment used known expected case names. Automatic discovery, general scaffold
validation, digesting, and table-row deletion were not implemented or validated.
It did not validate Testify, databases/containers, race detection, build tags, cgo,
multi-module projects, generic APIs, changed signatures, or crash recovery. Do not
turn those omissions into silent promises or silent support restrictions; exercise
needed cases during implementation and surface consequential limitations.

Temporary evidence, which may disappear and is not a runtime dependency:
`/private/tmp/kaba-go-spike-bye2c7up/REPORT.txt`, `results.json`, `experiment.py`,
`extend_field.go`, and the per-case event streams under `results/`.
The durable regression cases belong in Kaba's test suite during implementation.
