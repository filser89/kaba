# Runner and ownership contract

Read this reference when planning, writing, reviewing, fixing, or implementing tests.
Load `.kaba/config.yml` for the runner, commands, and permissions. Classify a path with
`$(git config kaba.scriptdir)/path-permissions.sh classify <path>`: `test`,
`implement`, `shared`, or `none`. Test support includes fixtures and helpers. A shared
path is writable in both sessions; feature-artifact and plan-lock restrictions still
apply. Explicit permission configurations have no `test_dir`; survey the configured
allow/exclude patterns and the runner's discovered files. Legacy RSpec configurations
use `test_dir`, `feature_dir`, and literal `test_writable` carve-outs.

## RSpec

Use the project's describe/context/it, factories, and shared-context conventions.
Identities are positional RSpec addresses such as `./spec/item_spec.rb[1:2]`.
Append examples after existing siblings to preserve those addresses. PIN files use the
leading `./` and the exact full description. An example's opening line carries
`# CRITERION-ID`. Mark a planned removal with
`skip: "REMOVED by <feature>"`; it must report pending. Ruby 3.3+ with Prism performs
structural digests and source cleanup. RSpec message-expectation, any-instance, and
`respond_to` matcher bans apply only to this runner.

## Go

Use package-local `_test.go` files, helpers, fakes, fixtures, and the project's assertion
library. Normal Testify assertions, local HTTP stubs, and fixture files are valid;
Testify suite registrations are outside the supported registration inventory.
Go-only operation requires Go and does not require Ruby or Prism.

Use the runner-discovered identity `IMPORT_PATH::TestName/subtest`. Group matching uses
slash boundaries. Copy addresses, file paths, and full descriptions from
`snapshot-tests.sh identities`; compose no existing identities manually. PIN file paths
are repository-relative and full descriptions equal the runtime test name. Any
post-test capture that uses scaffolding rejects every PIN, including an independent
package's PIN. Plan PINs only when the entire capture can execute against real code.

Supported registrations are named `func TestX(t *testing.T)` functions, literal
`t.Run("name", func(t *testing.T) { ... })` callbacks (including nested callbacks), and
ranges over literal anonymous struct slices. A slice may be the range expression or
one local variable assigned with `:=` or `var`. Each row has a literal, nonempty,
stable, unique name; each range has one direct `t.Run(tc.name, literalCallback)`.
Positional and keyed rows are supported. Normal setup, helper return values such as
`client := newTestClient(t)`, compile-time interface assertions, and `t.Parallel` are valid.
Dynamic names/tables, named table types, helper-generated registrations, Run aliases,
conditional registrations, duplicate normalized names, empty tables, runnable Example,
Fuzz, and suite registrations fail with diagnostics. Reordering rows preserves identity.
Ordinary comments and formatting do not affect structural digests; compiler directives,
imports, shared callbacks/setup, and referenced test-support declarations do.
Implicit variable initializers, `init`, and `TestMain` contribute to all tests in the
test executable, including both internal and external test packages. Referenced
same-package test-owned `.go` support participates in declaration digests, including
methods on referenced fake types that execute through interfaces. Imported
test-owned helper packages contribute their active source at package granularity,
including transitive imports: changing a declaration in that support requires planned
TOUCH/MODIFY coverage for the executable's affected tests. Ordinary production bodies
and files excluded by the selected build tags do not contribute.

Place `// CRITERION-ID` beside each function, literal registration, or table row that
covers that criterion. The marker guides review/fixes; scripts use AST identities.
Every automated behavioral outcome and named variant must map to real assertions and remain
locatable in source. Several criteria may share a coherent case; one criterion may require
several cases/evidence locations. Mark all covered IDs. Source/configuration inspection, command
verification, and manual runtime checks use explicit procedures/results outside the test-source
marker contract. Keep Delivery Obligations separate; do not manufacture tests for deliverables.

Mark a function or literal subtest removal with `t.Skip("REMOVED by <feature>")`.
For a table, give the affected row a `removedBy` string and use
`if tc.removedBy != "" { t.Skip("REMOVED by " + tc.removedBy) }` in the shared callback.
Adding that shared guard changes every affected case's body: plan TOUCH/MODIFY entries
for them. Marking a single row then changes only that row's digest. Skip only the leaf;
a parent skip hiding discovered children invalidates capture.

If declarations are missing, describe their established public contracts in the test
plan and provide minimal compilation scaffold sources under the package's
`testdata/kaba/<feature>/*.go`, with effective test ownership. Scaffolds may add missing
types, fields, functions, and methods; they may not replace existing business behavior.
Use default-return placeholder bodies and behavioral assertions that actually go red.
A blanket panic can abort the package and invalidate capture. The runner validates and
applies scaffolds only in post-test using a temporary overlay. Post-implementation runs
use real production code. Keep scaffold files through implementation and let
`cleanup-tests.sh` remove the recorded sources between features.

Field additions to existing generic structs and conflicting field import aliases fail
with diagnostics. The executed compatibility baseline is Go 1.27.0 on darwin/arm64;
the helper's Go 1.23 module declaration is not a tested minimum-version claim.

## Gates and commands

The public snapshot commands retain their stage responsibilities. Internally,
`test-runner.sh run|identities|digests --phase baseline|post-test|post-impl|cleanup`
selects the configured adapter. Go runs are uncached and require complete source/event
inventories. Build errors and missing child outcomes invalidate capture. Snapshot
comparison requires matching runner, package/tag selection, command, and Go build
context. Shell-wrapped Go commands, user overlays, nonempty GOFLAGS, selection filters,
explicit cache counts, race-mode snapshot commands, and unsupported flags fail closed.
The project's aggregate quality command may independently include race checks.

`banned-patterns.sh` inspects supported Go source and removal forms, explicitly reports
RSpec matcher bans as inapplicable, and preserves the RSpec pattern scan. It does not
run the aggregate project command during the intentionally red test session.
Implementation completion requires a successful configured `linter_command` and
`session-lock.sh check-dirty implement`, as well as post-implementation snapshot gates.
A failing command leaves completion blocked and the session lock armed.
Successful Go post-test comparison records which new and MODIFY tests must pass during
implementation. Post-implementation comparison requires those tests to pass and preserves
unrelated baseline failures. A Go post-test snapshot without these validated targets
must first pass `compare post-test`; capture alone is insufficient.
Successful post-test comparison also refreshes the scaffold manifest after valid
test-review edits. Cleanup rejects mismatched manifests without refreshing them.

Protected inventories include ignored test-owned fixtures, internal directory aliases
and their protected descendants, and nested Git fixture contents. Only the repository's
own Git metadata is excluded. Unrelated non-test links do not block capture; unsafe
test-owned links are rejected. Directory aliases protect both their targets and link
identity, including when the directory itself is shared or implementation-owned.

`cleanup-tests.sh` owns removal targets and exact rollback. Go cleanup requires lock-off,
completed valid snapshots, clean affected files, a fresh complete overlay-free green
run, locked-test comparison, and the configured quality command. It deletes exact marked
functions/subtests/rows and feature-recorded scaffolds, verifies the remaining identity
set and real suite, and restores exact bytes on failure. Imports made unused by a
removal are deleted using Go type information from the configured toolchain and build
tags. Retained source bytes, aliases, side-effect imports, and compiler directives are
preserved. Import analysis requires the original selected package to compile, as does
the fresh pre-cleanup suite. The agent invokes and reports
this script; it does not perform source deletion or rollback itself.

Legacy RSpec cleanup requires no feature-directory resolution. It verifies lock-off,
clean test-owned files, fresh results with no failures, pending removal markers, quality
before and after deletion, and the expected remaining count; positional RSpec identities
can change after deletion. An explicit `FEATURE_DIR` restricts removal to that feature.
It restores exact touched bytes on failure.
