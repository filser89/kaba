---
description: Decompose a feature specification's acceptance scenarios into granular, test-oriented acceptance criteria for the test session.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). The user may provide additional constraints, focus areas, or corrections to scope.

## Purpose

This command bridges the gap between a feature specification (written for stakeholders) and a test plan (written for the test suite). It takes the spec's acceptance scenarios and edge cases and produces a flat, exhaustive list of acceptance criteria — each one a single testable assertion that maps directly to one or more test examples.

This is a **thinking step**, not a writing step. No test code is produced. No implementation decisions are made. The output defines "what must be true after the test session."

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
   - The test directory is `test_dir` in `.kaba/config.yml` — read it from there; never infer it from project structure.
   - Once identified, scan it to understand what tests already exist. List the files — do NOT read every file in full, just note file paths and, for files that might overlap with this feature, read their high-level test organization (describe blocks, test names, etc.) to understand coverage.

4. **Extract testable surface from the spec**:
   - For each **acceptance scenario**: decompose into individual assertions. One scenario often contains multiple testable claims (e.g., "the system stores the record, derives field X from the input, and returns it with an id" contains three assertions: storage, derivation, and response content — split them).
   - For each **edge case**: produce one or more assertions.
   - For each **functional requirement**: check whether it's already covered by an acceptance scenario assertion. If not, add an assertion for it.
   - For each **success criterion**: check whether it's already covered. If not, flag it — success criteria are measurable outcomes, some may need dedicated tests.

5. **Classify each criterion**:
   - Derive categories from the spec's domain — do NOT use a fixed list. Group criteria by the layer or concern they test.
   - Typical categories might include model validations, model behavior, authentication, authorization/scoping, request/response, and integration — but use whatever grouping fits the actual spec.
   - Each category should be cohesive: a reader should be able to look at one category and understand the full testable surface for that concern.
   - If a criterion spans multiple categories, place it in the one it primarily validates and cross-reference the other.

6. **Check for gaps**:
   - Could a trivially wrong implementation pass all criteria? If yes, criteria are missing.
   - Are there implicit requirements in the spec's assumptions that aren't covered? (e.g., "delete is permanent" — should there be a test that confirms no soft-delete?)

7. **Cross-reference with existing tests**:
   - If tests already exist for related functionality (e.g., a model spec for a related entity), note which criteria are already covered and mark them as `[EXISTS]`.
   - For criteria that require modifying existing tests, mark them as `[MODIFY]` with the file path.
   - New criteria are marked `[NEW]`.

8. **Write the acceptance criteria document**: Output to `FEATURE_DIR/acceptance-criteria.md` using the format below.

9. **Self-validate the output**: Before reporting, verify the document is internally consistent:
   - Every acceptance scenario from the spec is covered by at least one criterion.
   - Every functional requirement is either covered by a criterion or explicitly noted as hook-level / out of scope in Gaps & Open Questions.
   - Every criterion has a Source reference that corresponds to an actual section in the spec (e.g., "US1-AS1", "FR-005", "Edge Case 3").
   - No duplicate criterion IDs exist.
   - No criterion assertion contains "and" joining two distinct testable claims — if found, split it.
   - Every criterion is classified into exactly one category.
   - If any check fails, fix the document before proceeding. Do NOT silently skip failures.

10. **Report**: Print a summary — total criteria count, breakdown by category and status (NEW/MODIFY/EXISTS), and any gaps or open questions.

## Output Format

The acceptance criteria document MUST follow this structure:

```markdown
# Acceptance Criteria: [Feature Name]

**Feature**: [feature branch name]
**Spec**: [relative path to spec.md]
**Created**: [DATE]
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
- **Assertion**: [Single testable statement in plain English]
- **Notes**: [Optional — context for the test writer, e.g., "needs factory with specific URL"]
- **Existing file**: [Only if MODIFY or EXISTS — path to existing spec file]

#### [Criterion ID]: [Short description]
...

<!-- Repeat for each criterion in this category -->

### [Next Category]

#### [Criterion ID]: [Short description]
...

<!-- Repeat for each category -->

## Gaps & Open Questions

- [Any gaps found in step 6]
- [Any ambiguities that need human input before the test session]
```

## Key Rules

- **One criterion = one assertion.** If you find yourself writing "and" in an assertion, split it.
- **Use spec language, not code language.** Say "the response includes the record's id" not "expect(response[:id]).to be_present". The test plan step will handle translation to framework-specific syntax.
- **Criterion IDs are stable references.** Use the format `[CATEGORY-NNN]` (e.g., `VAL-001`, `AUTH-003`, `SCOPE-002`). These IDs will be referenced in the test plan.
- **Do NOT make implementation decisions.** Don't decide controller names, method signatures, or routing. Use the same level of specificity as the spec — if the spec names an endpoint path, use it; if it says "the create operation," say that.
- **Do NOT write test code.** Not even pseudocode. This is a what-to-test document, not a how-to-test document.
- **Flag, don't guess.** If the spec is ambiguous about a testable behavior, add it to Gaps & Open Questions instead of inventing a criterion.