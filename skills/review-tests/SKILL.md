---
name: review-tests
disable-model-invocation: true
context: fork
description: Review the test suite for strength before implementation — could a terrible implementation pass these tests? Read-only; writes a severity-graded findings report.
---

At the load-context step, read `$(git config kaba.scriptdir)/../docs/test-runners.md` for the configured runner's
ownership, identity, source, criterion-marker, scaffolding, and cleanup contracts.
Apply that runner's branch to the steps below. RSpec describe blocks/factories map to
Go named functions/subtests/table rows and fixtures/helpers when `test_runner: go`.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). The user may narrow the review to specific files, criteria, or categories.

**This command runs forked (`context: fork`), and the arguments above are the only thing it
receives from the human.** A forked skill does not inherit the conversation: nothing said in the
test session — no escalation discussion, no "focus on X", no justification for why some assertion
was left thin — is visible here. That is deliberate. This is the adversarial gate, and a reviewer
that cannot see the implementer's reasoning cannot be talked out of a finding by it. Two
consequences: everything you need comes from disk or from the arguments above, so resolve it
explicitly and never assume prior context; and narrowing only works when the human passes it as
arguments, so treat an empty input as a full review rather than guessing at an intended scope.

### Codex isolation bridge

Codex currently loads this skill inline even though the frontmatter says `context: fork`. When a
collaboration tool is available that can spawn a subagent with `fork_turns: "none"`, do not run
the review in this agent unless its assigned task already contains `KABA_ISOLATED_REVIEWER=1`:

1. Before reading feature or test artifacts, spawn exactly one subagent with `fork_turns: "none"`.
2. Its task must begin with `KABA_ISOLATED_REVIEWER=1`, forbid further delegation, tell it to read
   this skill from `$(git config kaba.scriptdir)/../skills/review-tests/SKILL.md`, and pass only the
   human arguments supplied with this invocation. Do not copy any other conversation content.
3. Wait for that subagent to finish, relay its final summary, and stop. The parent must not perform
   any review steps or write `test-review.md` itself.

When the collaboration tool is unavailable, continue here: Claude's native `context: fork` has
already supplied the isolated context. An agent whose assigned task contains
`KABA_ISOLATED_REVIEWER=1` is the fresh Codex reviewer and continues below without spawning again.

**Scoped review mode**: If arguments contain criterion IDs (e.g. `DELETE-004 FMT-008`) or
explicit source/Delivery Obligation references (e.g. `FR-005 DO-002`), review only those scopes
and their affected evidence. Cross-reference IDs against criteria/spec and warn on invalid IDs;
if no valid scope remains, fall back to full mode. Preserve all unrelated findings when merging.

## Goal

Judge whether the tests and planned evidence constrain the approved behavior and expose
plausible incorrect implementations. Separation and review are coverage safeguards, not a
guarantee of correctness. The central question for every test is: *could a trivial or deliberately-wrong
implementation pass this?* Inspect whether every sourced behavioral obligation, related outcome, and named variant has
meaningful evidence. Mechanical snapshots protect identities and suite state; they do not
guarantee criterion coverage or prove that green tests imply full delivery completion.

This runs at the end of the test session (after `/kaba:implement-tests`), as the agent gate
before human review and Phase 3 implementation.

## Operating Constraints

**READ-ONLY EXCEPT ONE FILE**: Do not modify any file except the report at
`FEATURE_DIR/test-review.md`. Never edit test-owned paths (the configured permission classifier),
never write implementation code, never run the test suite or write a reference implementation.

**Project Rules Authority**: The project rules (CLAUDE.md/AGENTS.md, per `.kaba/config.yml`'s
`rules_files`) are non-negotiable. A violation of a MUST-level project rule in a test is
automatically CRITICAL.

**Review the approved contract without inventing requirements**: Compare the spec, criteria,
and evidence plan. Report sourced obligations missing upstream from criteria, missing required
variants/evidence, and needless implementation coupling that rejects legitimate conforming
implementations. At this test-stage checkpoint, check Delivery Obligation mapping and planned
verification, not completed deliverables or implementation-dependent manual checks. Those are
verified during implementation completion; their pending status is not a test handoff blocker.
Keep Delivery Obligations distinct from runtime evidence. Do not rewrite
requirements, edit criteria/plans/tests, choose unresolved policy, or repeat the banned-pattern
scan. An upstream gap is a finding with its source and consequence, not a new requirement.

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

- **REQUIRED**: Read `ACCEPTANCE` — the behavioral contract (IDs, behavior, related outcomes, required variants, evidence kinds).
- **REQUIRED**: Read `TEST_PLAN` — the criterion → required outcomes/variants → evidence-location mapping.
- Read `SPEC` for source fidelity, missing behavioral obligations, and separate Delivery Obligations.
- Read `CLAUDE.md` for project test conventions.
- Read the project rules (CLAUDE.md/AGENTS.md, per `.kaba/config.yml`'s `rules_files`) for
  project-wide constraints.
- Identify test-owned paths from `.kaba/config.yml` and the classifier; explicit configurations have no `test_dir`.

### 3. Build the review map

From `TEST_PLAN`, list every criterion ID, its related outcomes/named variants, and all
evidence locations it maps to. **In
scoped mode, map the selected criteria/source obligations and their affected evidence.** Read the actual test files and
locate each criterion's test — tests carry `# CRITERION-ID` (RSpec) or `// CRITERION-ID` (Go) at each
criterion-bearing example/function/subtest/table row, use it to match. Build, in memory, a table of
`criterion → required outcomes/variants → evidence (file:line/code or check procedure/result)`.
Inspect actual assertions and setup, not names or markers alone. In full mode, also trace spec
obligations to criteria and Delivery Obligations to their separate completion checks. In scoped
mode, inspect source dependencies of the selected criteria; leave unrelated findings untouched.

### 4. Core detection passes

For each criterion/test **in the review map** (all criteria in full mode; only the scoped criteria
in scoped mode), run the checks below against sourced requirements; report gaps instead of inventing policy.

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
with no evidence for required outcomes/variants. Manual/source/command evidence must have a
concrete location/procedure and expected result; it need not be a test block. Identify checks
that reasonably await implementation as pending, not falsely completed. Supported PIN/passed
and conforming MODIFY/passed are valid; required REMOVE-marked legacy tests may stay pending.

**D. Source completeness and coupling** — Flag a sourced behavior missing from criteria as an
upstream gap with the spec location and a concrete consequence. Flag unnecessary coupling only
with a plausible implementation that satisfies the approved behavior but the test rejects,
explaining the accidental structural constraint. Relevant side effects, ordering, concurrency,
and connected recovery journeys matter only when required by the source. Missing planned delivery
completion checks remain separate findings, not demands for completed deliverables or fake tests.

### 5. Hybrid escalation — prove every weakness with a stub

For every test flagged in pass A or B, construct the **weakest concrete implementation stub** (in
the report only — never written to a file) that makes that test pass. The stub is both the proof
and the false-positive filter:
- If you can write a stub that passes the cited test, the finding stands; include the stub.
- **If you cannot show a plausible incorrect implementation that passes the cited evidence,
  drop an assertion-weakness claim.** A localized missing-obligation/evidence gap instead cites
  its source, absent mapping, and concrete incorrect behavior that would escape detection.
  A coupling finding cites a conforming implementation rejected by the unnecessary assertion.
  A project-rule or delivery-check finding cites the exact rule/task and observed mismatch;
  it does not require an invented passing stub.

Strong tests (those that survive — no trivial stub passes them) get no finding.

### 6. Severity assignment

Assess mixed evidence per required outcome and named variant, using its planned evidence kind.
A source/command/manual check is valid with a suitable procedure and expected result; a check
that requires implementation may remain explicitly pending at the test handoff. Neither absence
of an automated assertion for that check nor its legitimate pending status is a finding.

- **CRITICAL** — a planned automated outcome a trivial/wrong implementation provably passes
  (stub shown), or with no real assertion; a violation of a MUST-level project rule in a test.
- **HIGH** — assertion materially weaker than the criterion; a sourced required outcome or
  variant without planned evidence (including a missing/invalid procedure or expected result
  for non-automated evidence); unnecessary coupling that blocks valid implementations; missing
  side-effect/negative evidence that lets a broad class of wrong implementations pass.
- **MEDIUM** — partial fidelity; low-risk boundary one-sidedness.
- **LOW** — cosmetic / readability that does not affect what the test constrains.

### 7. Write the report

Write the findings to `FEATURE_DIR/test-review.md` — the ONLY file this command writes — using the
Report Format below. Use stable, deterministic finding IDs (prefix `R`, numbered in source/criterion order).
Preserve existing IDs for the same issues during scoped merges; assign new findings unused IDs
so unrelated findings never collide or get renumbered.

**In scoped mode** — merge into the existing report instead of overwriting:

1. If `FEATURE_DIR/test-review.md` exists, read it and parse the Findings table.
2. For each scoped criterion/source obligation that **cleared** (no finding): remove its rows from the Findings table.
3. For each scoped criterion/source obligation that **still has findings**: replace its rows with updated findings, preserving stable IDs for the same issues.
4. Rows for criteria/source obligations **not in the scoped set**: leave untouched.
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

| ID | Criterion | Location (file:block) | Severity | Weakness | Counterexample / evidence | Recommendation |
|----|-----------|-----------------------|----------|----------|--------------|----------------|
| R1 | CREATE-010 | create_spec.rb > invalid url | HIGH | Asserts only status 422; does not pin which input was rejected | `def create; head :unprocessable_entity; end` | Assert the error points at the offending field (e.g. `/data/attributes/url`) |

(One row per finding. Use a minimal plausible passing incorrect implementation for assertion
weakness, source/absence evidence for upstream gaps, or a rejected conforming implementation
for coupling. Identify upstream gaps by their existing source reference instead of inventing IDs.)

## Strength Summary

- [Per-category notes: which areas are solid, which are thin. Name the strong tests explicitly so
  the reader knows they were reviewed and survived.]

## Next Actions

- [If NO-GO: the specific tests to strengthen before Phase 3, in priority order.]
- [If GO: optional improvements, or "No blocking issues — proceed to human review."]
```

## Key Rules

1. **Read-only except `test-review.md`.** Never modify test-owned paths (the configured permission classifier), never write implementation code, never run the suite.
2. **Prove findings concretely.** Assertion weakness requires a plausible passing incorrect
   implementation; upstream gaps require source + absent evidence + consequence; coupling
   requires a rejected conforming implementation. Keep delivery-check gaps distinct.
3. **Review source fidelity and evidence.** Include missing obligations/criteria/variants and
   needless implementation coupling; report upstream gaps without changing the contract.
   Do not invent policy or repeat the banned-pattern scan.
4. **Project rules violations are CRITICAL.**
5. **Advisory, not blocking.** The human review step makes the final go/no-go call.
6. **Deterministic.** Stable finding IDs and consistent counts when re-run without changes.
7. **Report zero issues gracefully.** Emit a clean GO report with the strength summary when no
   weaknesses are found.
8. **Scoped mode merges into the existing report.** Only the scoped criteria are re-reviewed, but
   the report reflects all findings (merged). The verdict applies to the full remaining set.

## Next Step

On a NO-GO verdict, point the user at `/kaba:fix-tests`, which applies these findings to the test
files and re-validates. On GO, the next step is the human review gate — the final call is theirs,
not this report's (Key Rule 5). Only after that does Phase 3 begin, with `/kaba:plan-code` in a
fresh session. Never present implementation as the automatic next step.

## Context

$ARGUMENTS
