---
description: Review the test suite for strength before implementation — could a terrible implementation pass these tests? Read-only; writes a severity-graded findings report.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). The user may narrow the review to specific files, criteria, or categories.

**Scoped review mode**: If the arguments contain criterion IDs (tokens matching `[A-Z]+-\d+`,
e.g. `DELETE-004 FMT-008`), enter scoped mode — only the listed criteria are reviewed. All other
criteria are skipped. Cross-reference each ID against `ACCEPTANCE` to confirm it exists; warn and
skip any invalid ID. If no valid IDs remain, fall back to full mode.

## Goal

Judge whether the test suite is **strong enough that making it green forces a correct
implementation**. The central question for every test is: *could a trivial or deliberately-wrong
implementation pass this?* `/kaba:implement-tests` already guarantees every criterion has *a*
test block (mechanical 1:1 mapping); this command judges whether those blocks actually
**constrain behavior**.

This runs at the end of the test session (after `/kaba:implement-tests`), as the agent gate
before human review and Phase 3 implementation.

## Operating Constraints

**READ-ONLY EXCEPT ONE FILE**: Do not modify any file except the report at
`FEATURE_DIR/test-review.md`. Never edit the test directory (`test_dir` in `.kaba/config.yml`),
never write implementation code, never run the test suite or write a reference implementation.

**Project Rules Authority**: The project rules (CLAUDE.md/AGENTS.md, per `.kaba/config.yml`'s
`rules_files`) are non-negotiable. A violation of a MUST-level project rule in a test is
automatically CRITICAL.

**Review tests against existing criteria only**: Do NOT re-derive acceptance criteria from the
spec, do NOT re-scan for banned patterns, and do NOT flag brittleness/over-specification — those
are owned by other steps (`/kaba:acceptance-criteria`, the
`implement-tests` inline scan) and are out of scope here. Load `spec.md` only for the domain
understanding needed to judge fidelity.

## Execution Steps

### 1. Resolve feature paths

Run `$(git config kaba.scriptdir)/resolve-feature.sh` from the repo root. It prints three
`KEY=value` lines — `REPO_ROOT`, `FEATURE_DIR`, `FEATURE_SPEC` — read them line-by-line (never
`eval`; a path may contain spaces). For single quotes in args like "I'm Groot", use escape syntax:
e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

Derive:
- `ACCEPTANCE = FEATURE_DIR/acceptance-criteria.md`
- `TEST_PLAN = FEATURE_DIR/test-plan.md`
- `SPEC = FEATURE_SPEC`

If `ACCEPTANCE` or `TEST_PLAN` is missing, ERROR and stop — suggest running
`/kaba:plan-tests` then `/kaba:implement-tests` first.

### 2. Load context

- **REQUIRED**: Read `ACCEPTANCE` — the behavioral contract (each criterion's ID and assertion).
- **REQUIRED**: Read `TEST_PLAN` — the criterion → file → describe-block mapping.
- Read `SPEC` for domain understanding (used only to judge fidelity).
- Read `CLAUDE.md` for project test conventions.
- Read the project rules (CLAUDE.md/AGENTS.md, per `.kaba/config.yml`'s `rules_files`) for
  project-wide constraints.
- The test directory is `test_dir` in `.kaba/config.yml` — read it from there; never infer it from project structure.

### 3. Build the review map

From `TEST_PLAN`, list every criterion ID and the test file + describe block it maps to. **In
scoped mode, only map the criteria matching the provided IDs.** Read the actual test files and
locate each criterion's test — the specs carry a trailing `# CRITERION-ID` comment on each
example, use it to match. Build, in memory, a table of
`criterion → assertion (from criteria) → located test (file:line, code)`.

### 4. Core detection passes

For each criterion/test **in the review map** (all criteria in full mode; only the scoped criteria
in scoped mode), run the three core checks. These are the ONLY checks (see Operating Constraints
for what is out of scope).

**A. Assertion strength / gameability** — Reason statically about the weakest implementation that
would satisfy the assertion. Flag a test when a trivial or deliberately-wrong impl would pass it,
e.g.:
- status-only checks that don't pin which input/branch produced the status
- presence-not-value checks (asserts a field exists, not that it holds the right value)
- tautologies (asserts on the factory's own input without exercising derived behavior)
- one-sided boundaries (reject side tested but not accept side, or vice-versa)
- missing side-effect / negative assertions (e.g. asserts a 4xx but not that nothing was persisted/changed)

**B. Criterion↔test fidelity** — Does the test assert what the criterion *states*, or something
weaker/adjacent? (Criterion: "domain is derived from the URL host" vs. a test that only checks
domain is present.)

**C. Coverage depth** — Is the mapped block present and meaningful? Flag missing, empty, pending
(`skip`/`xit`/`pending`), or trivially-true blocks. Also surface any criterion ID in the plan
with no locatable test — a hole `implement-tests` should have caught.

### 5. Hybrid escalation — prove every weakness with a stub

For every test flagged in pass A or B, construct the **weakest concrete implementation stub** (in
the report only — never written to a file) that makes that test pass. The stub is both the proof
and the false-positive filter:
- If you can write a stub that passes the cited test, the finding stands; include the stub.
- **If you cannot write such a stub, the finding is a false positive — drop it.**

Strong tests (those that survive — no trivial stub passes them) get no finding.

### 6. Severity assignment

- **CRITICAL** — a criterion a trivial/wrong impl provably passes (stub shown); a criterion with
  no real assertion; a violation of a MUST-level project rule in a test.
- **HIGH** — assertion materially weaker than the criterion; a missing side-effect/negative
  assertion that lets a broad class of wrong impls pass.
- **MEDIUM** — partial fidelity; low-risk boundary one-sidedness.
- **LOW** — cosmetic / readability that does not affect what the test constrains.

### 7. Write the report

Write the findings to `FEATURE_DIR/test-review.md` — the ONLY file this command writes — using the
Report Format below. Use stable, deterministic finding IDs (prefix `R`, numbered in criterion
order) so re-running without changes yields consistent IDs and counts.

**In scoped mode** — merge into the existing report instead of overwriting:

1. If `FEATURE_DIR/test-review.md` exists, read it and parse the Findings table.
2. For each scoped criterion that **cleared** (no finding): remove its row from the Findings table.
3. For each scoped criterion that **still has a finding**: replace its row with the updated finding.
4. Rows for criteria **not in the scoped set**: leave untouched.
5. Recompute Summary counts and Verdict from the remaining rows.
6. Recompute Next Actions from remaining findings.
7. **Leave Strength Summary as-is** — a scoped review cannot regenerate full-suite prose.
8. Write the merged report to `FEATURE_DIR/test-review.md`.

If no existing report exists, write only the scoped results (nothing to merge into).

### 8. Advisory verdict

Decide the verdict (advisory — the human review step owns the final go/no-go; nothing is
hard-blocked):
- Any **CRITICAL or HIGH** finding ⇒ recommend **NO-GO** (strengthen the cited tests before Phase 3).
- Only **MEDIUM/LOW** ⇒ **GO** with improvement suggestions.
- No findings ⇒ clean **GO**.

Print a short summary to the conversation (counts + verdict + report path) and stop.

## Report Format

```markdown
# Test Review: [Feature Name]

**Feature**: [branch] | **Reviewed**: [DATE] | **Verdict**: GO | NO-GO (advisory) | **Scope**: full | [criterion IDs]

## Summary

- Criteria reviewed: [N] / [N] [if scoped: "(scoped: ID1, ID2, ...)"]
- Findings: [C] critical, [H] high, [M] medium, [L] low
- Verdict: [GO | NO-GO] — [one-line rationale]

## Findings

| ID | Criterion | Location (file:block) | Severity | Weakness | Passing stub | Recommendation |
|----|-----------|-----------------------|----------|----------|--------------|----------------|
| R1 | CREATE-010 | create_spec.rb > invalid url | HIGH | Asserts only status 422; does not pin which input was rejected | `def create; head :unprocessable_entity; end` | Assert the error points at the offending field (e.g. `/data/attributes/url`) |

(One row per finding. Keep the stub to the minimum that passes the cited test.)

## Strength Summary

- [Per-category notes: which areas are solid, which are thin. Name the strong tests explicitly so
  the reader knows they were reviewed and survived.]

## Next Actions

- [If NO-GO: the specific tests to strengthen before Phase 3, in priority order.]
- [If GO: optional improvements, or "No blocking issues — proceed to human review."]
```

## Key Rules

1. **Read-only except `test-review.md`.** Never modify the test directory (`test_dir` in
   `.kaba/config.yml`), never write implementation code, never run the suite.
2. **Every weakness finding MUST carry a concrete passing stub.** No stub ⇒ drop the finding.
   This is the false-positive filter.
3. **Core checks only.** Assertion strength, criterion↔test fidelity, coverage depth. Do NOT
   re-derive criteria, re-scan banned patterns, or flag brittleness — those belong to other steps.
4. **Project rules violations are CRITICAL.**
5. **Advisory, not blocking.** The human review step makes the final go/no-go call.
6. **Deterministic.** Stable finding IDs and consistent counts when re-run without changes.
7. **Report zero issues gracefully.** Emit a clean GO report with the strength summary when no
   weaknesses are found.
8. **Scoped mode merges into the existing report.** Only the scoped criteria are re-reviewed, but
   the report reflects all findings (merged). The verdict applies to the full remaining set.

## Context

$ARGUMENTS
