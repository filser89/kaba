# Test Plan: [FEATURE]

**Feature**: `[###-feature-name]` | **Spec**: [link to spec.md]
**Acceptance Criteria**: [link to acceptance-criteria.md]

**Note**: This template is filled in by the `/kaba:plan-tests` command. See `templates/test-plan-template.md` in the kaba plugin for the format reference. All paths, extensions, and naming patterns must use the project's actual conventions.

## Summary

- Test files: [N] ([N] new, [N] modify, [N] existing)
- Factories: [N] ([N] new, [N] existing)
- Shared helpers: [N] ([N] new, [N] existing)
- Behavioral criteria mapped (unique IDs): [N] / [N total from acceptance criteria]
- Required outcomes/variants mapped: [N] / [N]
- Non-automated runtime evidence: [N] planned checks
- Delivery Obligations: [N] separate completion tasks
- Contract deltas: [N]
- Invalidation sweep: [N] examples hit — [N] keep / [N] modify / [N] remove

<!-- Runner contract: read $(git config kaba.scriptdir)/../docs/test-runners.md.
RSpec uses positional identities and describe/context/it. Go uses import path plus
runtime name, named functions/literal subtests/literal anonymous struct table rows.
Copy existing identities from snapshot-tests.sh identities. Explicit ownership has
no test_dir. For Go include planned test-owned scaffold sources under the package's
testdata/kaba/<feature>/*.go only when declarations are missing. PIN requires an
entirely overlay-free capture. Criterion markers: # CRITERION-ID (RSpec),
// CRITERION-ID (Go). Removal uses framework-specific leaf markers. -->

## Test Files

<!--
  ACTION REQUIRED: Add one entry per test file using the format below.
  Map every automated criterion and its named required variants to one or more files.
  Related outcomes can share a coherent test; one test can cover several criteria.
  List ALL criterion IDs explicitly — do NOT use ranges.
  Use the project's actual file paths, extensions, and naming conventions.
-->

### [file path with extension] ([NEW | MODIFY | EXISTS])

- **Criteria**: [e.g., VAL-001, VAL-002, VAL-003, DOM-001, DOM-002]
- **Describe blocks**:
  - `[top-level test group]`
    - `[nested group or context]`
      - covers: [e.g., VAL-001, VAL-002, VAL-003]
    - `[nested group or context]`
      - covers: [e.g., DOM-001, DOM-002]
- **Dependencies**: [e.g., order factory, customer factory, authenticated request helper]

<!-- Repeat for each test file. Every automated criterion ID MUST appear in at least one covers: line; identify the
required outcomes/variants covered at each location. -->

## Invalidation Sweep

<!--
  ACTION REQUIRED: One subsection per contract delta (see the Invalidation Sweep Rules in
  the plan-tests command). Record the probes used, the files hit, and a disposition for
  EVERY hit example. This section is the auditable evidence that discovery of invalidated
  tests was suite-wide; the Planned State Changes table below is derived from its
  MODIFY/REMOVE dispositions. If the feature changes no existing behavior, state
  "No contract deltas — purely additive feature." and delete the delta subsection below.
-->

### CD-[N] — [old contract] → [new contract] ([source: FR / criterion / clarification])

- **Kind**: [unconditional | conditional on: <state that must exist>]
- **Probes**: `[probe]` (request boundary); `[probe]` (storage boundary)
- **Files hit**: [list]
- **Dispositions**:

| Example (address) | Description | Disposition | Reason |
|---|---|---|---|
| [adapter identity string] | [exact recorded description] | [KEEP \| MODIFY \| REMOVE] | [one line] |
| [file path] (collective) | — | KEEP | [shared reason: the state-entering action never occurs in this file] |

<!-- Repeat for each contract delta. Every hit example has exactly one disposition. -->

## Planned State Changes

<!--
  Machine-enforced allowlist of test-suite state changes this feature intends.
  plan-tests generates test-plan.json (schema v3) from this table, whole, on
  every run. Four actions:
  - MODIFY: existing example, expected to change status. Lands on its Expected
    landing at post-test — `failed` normally; `passed` only for a conforming
    modify (the new-contract assertion already holds).
  - REMOVE: existing example, skip-marked for removal. Lands `pending`.
  - PIN: NEW example pinning already-conforming behavior. Lands `passed`. No
    address — identity is file + the exact planned full description.
  - TOUCH: existing example, content edit with NO status change. Lands
    `unchanged` (digest drift excused, status flip never).
  - A group address (e.g. `[1:2]` with no third segment) allowlists every example
    under it (MODIFY/REMOVE/TOUCH only; PIN is always exact).
-->

| Action | Identity (address) | Description | Expected landing | Reason |
|--------|--------------------|-------------|------------------|--------|
| [MODIFY/REMOVE/PIN/TOUCH] | [address, or — for PIN] | [description] | [failed/pending/passed/unchanged] | [reason] |

## Factories / Fixtures

<!--
  ACTION REQUIRED: Add one entry per entity referenced in the acceptance criteria.
  "Factory" means any test data setup mechanism the project uses: factories, fixtures,
  builders, seed helpers, etc. Use the project's own terminology and conventions.
  If a factory already exists in the project, mark it EXISTS and note any new traits needed.
-->

### [factory name] ([NEW | MODIFY | EXISTS])

- **File**: [path to factory/fixture file]
- **Base attributes**: [e.g., total (sequential integer), status ("pending"), customer (association)]
- **Traits/variants**:
  - [variant name] — [what it changes from the base, and why it is needed]
  - [variant name] — [what it changes from the base, and why it is needed]
- **Associations**: [e.g., customer factory — or "none"]
- **Used by**: [comma-separated list of test files that need this factory]

<!-- Repeat for each factory. Associations MUST be explicit. Every file in Used-by MUST list this factory in its Dependencies. -->

## Shared Helpers

<!--
  ACTION REQUIRED: Add one entry per shared helper, reusable setup, or custom assertion.
  Extract when 3+ test files share the same pattern. Use judgment for 2 files. Do NOT extract for 1 file.
  [REMOVE THIS SECTION IF NO SHARED HELPERS ARE NEEDED]
-->

### [Helper name] ([NEW | MODIFY | EXISTS])

- **File**: [path to helper file]
- **Type**: [shared_setup | shared_assertions | helper_method | custom_matcher]
- **Purpose**: [e.g., Sets up authorization header with a valid token for request tests]
- **Interface**: [e.g., `authenticated_headers(credential)` returns a headers hash/dict]
- **Used by**: [comma-separated list of test files that reference this helper]

<!-- Repeat for each shared helper. Every file in Used-by MUST list this helper in its Dependencies. -->

## Criteria Mapping

<!--
  ACTION REQUIRED: Map every behavioral criterion, related required outcome, and named variant.
  Multiple evidence locations per criterion and several criteria per coherent test are valid.
  Count unique criteria. Every required outcome/variant has explicit coverage; repeated IDs
  identify the distinct portion established by each location. Source/configuration inspection,
  command verification, and manual checks name concrete artifacts/procedures and expected results.
  Delivery Obligations belong in their separate section, not fake test-file rows.
-->

| Criterion ID | Required outcomes / named variants | Evidence kind | Location / procedure | Expected result |
|---|---|---|---|---|
| [ID] | [outcomes and variant names] | [automated test / source/configuration inspection / command verification / manual check] | [file + test name, artifact, or exact check procedure] | [what establishes the behavior] |

<!-- Continue for ALL behavioral criteria and required variants. -->

## Delivery Obligations

| Obligation ID | Source | Deliverable | Completion check |
|---|---|---|---|
| [DO-NNN] | [spec reference] | [documentation, configuration example, CI/setup verification, or completion task] | [concrete review/check] |

<!-- Preserve every known delivery task. Do not assign these to fake test files. Runtime
configuration behavior, security, deadlines, and user-visible setup belong in Criteria Mapping. -->
