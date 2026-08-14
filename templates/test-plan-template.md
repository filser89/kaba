# Test Plan: [FEATURE]

**Feature**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link to spec.md]
**Acceptance Criteria**: [link to acceptance-criteria.md]

**Note**: This template is filled in by the `/kaba:plan-tests` command. See `templates/test-plan-template.md` in the kaba plugin for the format reference. All paths, extensions, and naming patterns must use the project's actual conventions.

## Summary

- Test files: [N] ([N] new, [N] modify, [N] existing)
- Factories: [N] ([N] new, [N] existing)
- Shared helpers: [N] ([N] new, [N] existing)
- Criteria mapped: [N] / [N total from acceptance criteria]
- Contract deltas: [N]
- Invalidation sweep: [N] examples hit — [N] keep / [N] modify / [N] remove

## Test Files

<!--
  ACTION REQUIRED: Add one entry per test file using the format below.
  Assign every criterion from acceptance-criteria.md to exactly one file.
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

<!-- Repeat for each test file. Every criterion ID in Criteria MUST appear in exactly one covers: line. -->

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
  Machine-enforced allowlist of existing tests this feature intends to change. plan-tests
  generates test-plan.json from this table verbatim; the compare gate consults only the
  JSON. Derived from the Invalidation Sweep: every MODIFY/REMOVE disposition above becomes
  a row; a row may also arise outside the sweep with its own recorded reason. If the
  feature touches no existing tests, state "None" — the JSON is still emitted,
  empty.

  - Addresses and descriptions are copied from the identity scan — never composed by hand.
  - A group address (e.g. `[1:2]` with no third segment) allowlists every example under it.
  - MODIFY: the test is expected to land red at post-test. REMOVE: the test will be
    skip-marked in-session and deleted by the cleanup script after the feature.
-->

| Action | Identity (address) | Description | Reason |
|--------|--------------------|-------------|--------|
| [MODIFY \| REMOVE] | [adapter identity string, e.g. ./spec/models/x_spec.rb[1:2]] | [exact recorded description] | [why this test must change / is obsolete] |

## Factories

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
  ACTION REQUIRED: Fill this table with one row per criterion from acceptance-criteria.md.
  This table is the CONTRACT — the implement-tests step MUST follow it exactly.
  Every criterion MUST appear exactly once. No omissions, no duplicates.
-->

| Criterion ID | Test File | Describe Block |
|---|---|---|
| [ID] | [file path] | [test group path, e.g., Order > validations > total] |

<!-- Continue for ALL criteria. -->