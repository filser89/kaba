---
name: acceptance-criteria
disable-model-invocation: true
description: Decompose a feature specification's acceptance scenarios into behavioral acceptance criteria with explicit required variants and evidence for the test session.
---

At the load-context step, read `$(git config kaba.scriptdir)/../docs/test-runners.md` for the configured runner's
ownership, identity, source, criterion-marker, scaffolding, and cleanup contracts.
Apply that runner's branch to the steps below. RSpec describe blocks/factories map to
Go named functions/subtests/table rows and fixtures/helpers when `test_runner: go`.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). The user may provide additional constraints, focus areas, or corrections to scope.

## Purpose

This command bridges the gap between a feature specification (written for stakeholders) and a test plan (written for the test suite). It takes the spec's acceptance scenarios and edge cases and produces a flat, exhaustive list of acceptance criteria — each one an observable behavior under stated preconditions and a trigger, with its related
required outcomes, named variants, and evidence kind. Delivery Obligations stay separate.

This is a **thinking step**, not a writing step. No test code is produced. No implementation decisions are made. The output defines the required behavior and evidence to prepare, including checks that
await implementation, while preserving separate delivery completion tasks.

## Outline

1. **Resolve feature paths, then check for a prior run**: Run `$(git config kaba.scriptdir)/resolve-feature.sh` from the repo root. It prints three `KEY=value` lines — `REPO_ROOT`, `FEATURE_DIR`, `FEATURE_SPEC` — read them line-by-line (never `eval`; a path may contain spaces).
   - **Prior-run gate — resolve this BEFORE reading the spec.** A re-run regenerates the criteria from scratch, so the gate must come before any analysis spends tokens, not merely before the write. Run `$(git config kaba.scriptdir)/check-artifacts.sh acceptance-criteria` from the repo root and read its `KEY=value` lines:
     - `PRIOR_RUN=yes` — STOP and ask the user, naming what `EXISTING` lists (and mentioning `EMPTY` if non-empty, which means the previous run crashed part-way): "`acceptance-criteria.md` already exists for this feature — a prior run of `/kaba:acceptance-criteria` completed. Overwrite? The previous version is not recoverable (feature artifacts are untracked at this stage), and a re-run is a fresh derivation, not a reproduction." Ask, then **end your turn** — do not answer yourself and do not proceed in the same response. Use `AskUserQuestion` if it is available. Continue only on an explicit yes.
     - `PRIOR_RUN=no` — proceed.
     - `PRIOR_RUN=unknown`, a non-zero exit, or no `PRIOR_RUN=` line at all — STOP and report the script's stderr verbatim. **Absence of an answer is never "no."**
   - Only then read the spec from `FEATURE_SPEC` (i.e. `FEATURE_DIR/spec.md`). If no spec exists, ERROR and stop.

2. **Load context**:
   - Read the project rules (CLAUDE.md/AGENTS.md, per `.kaba/config.yml`'s `rules_files`) for project-wide constraints.
   - Read `CLAUDE.md` for project conventions (test framework, auth format, model names, etc.).

3. **Identify the test directory**:
   - Identify test-owned paths from `.kaba/config.yml` and the classifier; explicit configurations have no `test_dir`.
   - Once identified, scan it to understand what tests already exist. List the files — do NOT read every file in full, just note file paths and, for files that might overlap with this feature, inspect their high-level organization to locate candidates, then read the actual setup and
     assertions before claiming coverage. Test names alone are not evidence.

4. **Extract testable surface from the spec**:
   - For each **acceptance scenario**: identify its observable behavior, preconditions, trigger, and related required outcomes. Keep
     outcomes of the same behavior together; split when distinct triggers, states, failure
     mechanisms, or verification methods need separate cases. Enumerate named required variants
     so grouping never erases a sourced boundary or failure case.
   - For each **edge case**: produce or extend behavioral criteria, retaining distinct relevant variants.
   - For each **functional requirement**: check whether its observable behavior is covered by a criterion. If not, add or extend a
     criterion. Put known documentation/configuration examples/CI/setup completion work under
     Delivery Obligations, preserving its source and concrete completion check.
   - For each **success criterion**: check whether the observable outcome is covered. If not, map its evidence or flag the
     unresolved expected result; do not silently omit it.

5. **Classify each criterion**:
   - Derive categories from the spec's domain — do NOT use a fixed list. Group criteria by the layer or concern they test.
   - Typical categories might include model validations, model behavior, authentication, authorization/scoping, request/response, and integration — but use whatever grouping fits the actual spec.
   - Each category should be cohesive: a reader should be able to look at one category and understand the full testable surface for that concern.
   - If a criterion spans multiple categories, place it in the one it primarily validates and cross-reference the other.

6. **Bounded completeness audit**: For each sourced behavior, consider only relevant dimensions:
   - Input boundaries: distinguish missing from malformed, and accept/reject sides of stated limits.
   - State and sequences: if credentials/request isolation are in scope, include a successful
     authenticated request followed by a credential-free request, not only fresh missing input.
     For stateful journeys, examine prior success, retry, interruption, and recovery when sourced.
   - Failure mechanisms: distinguish a zero-byte normal EOF from a read error when stream failures
     matter; identify required transport forms rather than assuming one representation covers all.
   - Bounds: byte/size bounds and elapsed-time/wait deadlines prove different guarantees.
   - Effects: include meaningful side-effect absence, ordering, idempotency, and concurrency
     checks when the source requires them.
   Record a concrete plausible incorrect implementation for a suspected gap and trace the
   expected outcome to the source. If the source leaves it unsettled, report an Open Question
   instead of choosing policy. This is a relevance check, not a Cartesian product or a universal
   authentication checklist. Keep documentation/configuration examples/CI/setup completion tasks
   in Delivery Obligations; runtime configuration, security, deadlines, and user-visible setup
   behavior remain behavioral criteria.

7. **Cross-reference with existing tests**:
   - If tests already exist for related functionality (e.g., a model spec for a related entity), inspect actual assertions/evidence for every required outcome and named variant before marking
     a criterion `[EXISTS]`. Cite exact locations and what they prove; partial coverage is not EXISTS.
   - For criteria that require modifying existing tests, mark them as `[MODIFY]` with the file path.
   - New criteria are marked `[NEW]`.

8. **Write the acceptance criteria document**: Output to `FEATURE_DIR/acceptance-criteria.md` using the format below.

9. **Self-validate the output**: Before reporting, verify the document is internally consistent:
   - Every acceptance scenario from the spec is covered by at least one criterion.
   - Every behavioral requirement is covered by a criterion or explicitly identified as an
     unresolved evidence/contract gap. Every known delivery task remains in Delivery Obligations
     with its source and completion check; it is not a fake behavioral criterion.
   - Every criterion has a Source reference that corresponds to an actual section in the spec (e.g., "US1-AS1", "FR-005", "Edge Case 3").
   - No duplicate criterion IDs exist.
   - Related outcomes stay together; distinct required input/state/sequence/failure/transport
     variants are explicit, and every required outcome has a planned evidence kind.
   - Every criterion is classified into exactly one category.
   - If any check fails, fix the document before proceeding. Do NOT silently skip failures.

10. **Report**: Print a summary — total criteria count, breakdown by category and status (NEW/MODIFY/EXISTS), and any gaps or open questions.

## Output Format

The acceptance criteria document MUST follow this structure:

```markdown
# Acceptance Criteria: [Feature Name]

**Feature**: [feature branch name]
**Spec**: [relative path to spec.md]
**Status**: Draft

## Summary

- Total criteria: [N]
- New: [N] | Modify: [N] | Exists: [N]
- Categories: [list]

## Criteria

<!-- Repeat this category block for each concern area (e.g., validations, authentication, scoping, request/response). -->
<!-- Each category will contain multiple criteria. -->

### [Category Name] (e.g., "Model Validations — [Entity]")

#### [Criterion ID]: [Short description]
- **Status**: [NEW | MODIFY | EXISTS]
- **Source**: [Which spec section — e.g., "US1-AS1", "Edge Case 3", "FR-005"]
- **Behavior**: [Preconditions and trigger → related required observable outcomes]
- **Required variants**: [Named distinct cases with their expected outcomes; explicit "none" if no additional variants are sourced]
- **Evidence kind**: [Automated test | source/configuration inspection | command verification | manual check; identify what each proves]
- **Notes**: [Optional — context for the test writer, e.g., "needs factory with specific URL"]
- **Existing file**: [Only if MODIFY or EXISTS — path to existing spec file]

#### [Criterion ID]: [Short description]
...

<!-- Repeat for each criterion in this category -->

### [Next Category]

#### [Criterion ID]: [Short description]
...

<!-- Repeat for each category -->

## Delivery Obligations

- [DO-NNN — source, deliverable, completion check; preserve from spec, separate from behavioral criteria]

## Gaps & Open Questions

- [Any gaps found in step 6, with source and concrete incorrect behavior that could survive]
- [Any ambiguities that need human input before the test session]
```

## Key Rules

- **Classify obligations by what they require.** A security heading or functional-requirement
  label does not make every clause runtime behavior. Split mixed clauses with their source
  references intact: documentation, example/config packaging, tracked placeholders, ignored
  `.env` files, and version-control hygiene checks stay Delivery Obligations; runtime secret
  disclosure and security guarantees stay behavioral criteria. Retain every sourced obligation
  without inventing behavior.

- **One criterion = one observable behavior.** Keep related outcomes together and name every
  required variant. Several assertions or evidence locations may establish one behavior, and
  one coherent test may establish several criteria. Preserve accountability for every outcome.
- **Use spec language, not code language.** Say "the response includes the record's id" not "expect(response[:id]).to be_present". The test plan step will handle translation to framework-specific syntax.
- **Criterion IDs are stable references.** Preserve existing IDs for the same behavior. For new
  criteria, use the format `[CATEGORY-NNN]` (e.g., `VAL-001`, `AUTH-003`, `SCOPE-002`). These IDs will be referenced in the test plan.
- **Do NOT make implementation decisions.** Don't decide controller names, method signatures, or routing. Use the same level of specificity as the spec — if the spec names an endpoint path, use it; if it says "the create operation," say that.
- **Do NOT write test code.** Not even pseudocode. This is a what-to-test document, not a how-to-test document.
- **Flag, don't guess.** If the spec is ambiguous about a testable behavior, add it to Gaps & Open Questions instead of inventing a criterion.

## Next Step

Once the criteria are written, point the user at `/kaba:plan-tests` — it turns these criteria into
the test plan that `/kaba:implement-tests` then follows. If **Gaps & Open Questions** came out
non-empty, say so plainly: those want answers, or another `/kaba:clarify` pass, before a test plan
is built on top of them.
