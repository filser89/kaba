---
name: fix-tests
disable-model-invocation: true
description: Read test-review findings, apply mechanical fixes to test files, interactively resolve escalated findings, re-validate via snapshot and banned-pattern scan, and write an audit log.
---

At the load-context step, read `$(git config kaba.scriptdir)/../docs/test-runners.md` for the configured runner's
ownership, identity, source, criterion-marker, scaffolding, and cleanup contracts.
Apply that runner's branch to the steps below. RSpec describe blocks/factories map to
Go named functions/subtests/table rows and fixtures/helpers when `test_runner: go`.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). The user may narrow the scope to specific findings, criteria, or files.

## Goal

Strengthen flagged tests so a re-review can confirm the suite constrains behavior correctly.
`/kaba:review-tests` identifies *what* is weak; this command *fixes* it — mechanically where
possible, interactively where judgment is needed.

This runs after `/kaba:review-tests` produces a NO-GO verdict. It is a **test-session command**
— it only modifies test files, never writes implementation code.

## Operating Constraints

**TEST FILES + ONE REPORT**: Only modify files in test-owned paths (the configured permission classifier) and write `FEATURE_DIR/test-fixes.md`. Never write implementation code.

**Project Rules Authority**: The project rules (CLAUDE.md/AGENTS.md, per `.kaba/config.yml`'s
`rules_files`) are non-negotiable. A fix that would introduce a project rules violation is itself
a bug — fix the fix.

**Scope and certainty determine classification**: Whether a finding is fixed mechanically or
escalated to the human depends entirely on whether the agent knows the exact fix and whether it
stays within the same file without side effects. Severity (CRITICAL/HIGH/MEDIUM/LOW) is irrelevant
to this classification.

## Execution Steps

### 1. Resolve feature paths

Run `$(git config kaba.scriptdir)/resolve-feature.sh` from the repo root. It prints three
`KEY=value` lines — `REPO_ROOT`, `FEATURE_DIR`, `FEATURE_SPEC` — read them line-by-line (never
`eval`; a path may contain spaces). For single quotes in args like "I'm Groot", use escape syntax:
e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

Derive:
- `TEST_REVIEW = FEATURE_DIR/test-review.md`
- `ACCEPTANCE = FEATURE_DIR/acceptance-criteria.md`
- `SPEC = FEATURE_SPEC`

If `TEST_REVIEW` is missing, ERROR and stop — suggest running `/kaba:review-tests` first.
If `ACCEPTANCE` is missing, ERROR and stop — suggest running `/kaba:acceptance-criteria` first.

### 2. Load context

- **REQUIRED**: Read `TEST_REVIEW` — the findings to process.
- **REQUIRED**: Read `ACCEPTANCE` — the behavioral contract (each criterion's ID, behavior, related outcomes, required variants, and evidence kinds).
- Read `SPEC` for domain understanding.
- Read `CLAUDE.md` for project test conventions and banned patterns.
- Read the project rules (CLAUDE.md/AGENTS.md, per `.kaba/config.yml`'s `rules_files`) for
  project-wide constraints.
- Identify test-owned paths from `.kaba/config.yml` and the classifier; explicit configurations have no `test_dir`.

### 3. Check verdict

If `test-review.md` has a **GO** verdict (no findings), report: "Review already passed with GO.
Nothing to fix. Proceed to human review." and stop. This is not an error — the human may run
fix-tests out of habit or as part of a scripted flow.

### 4. Classify findings

For each finding in the report's Findings table, classify as **mechanical** or **escalated**.
An upstream missing requirement/criterion/evidence-plan entry or Delivery Obligation check is
not a same-file test fix. Report the precise source and missing contract mapping for the human
to resolve through specify/clarify/acceptance-criteria/plan-tests as appropriate; never invent
policy, edit those artifacts here, or manufacture a test for a delivery task.

**Mechanical** — the agent knows the exact fix and it stays within the same file without side
effects:
- Strengthening an assertion in an existing test block (swap a matcher, add a constraint)
- Adding a persistence check (e.g., reload before asserting)
- Adding new test examples in the same group when the fix is clear and specific
- Adding a new group/context if the recommendation specifies exactly what to test

**Escalated** — the fix would ripple beyond the file, or the agent doesn't know the exact right
answer:
- Requires moving tests between files
- Requires changing shared helpers or factories
- Requires restructuring that could affect other criterion coverage
- Multiple valid approaches and the choice has trade-offs the human should weigh

The question is: can the agent fix this by editing within the flagged test file, without touching
anything else, and be confident it's the right fix? Yes → mechanical. No → escalated.

### 5. Apply mechanical fixes

For each mechanical finding:
1. Read the test file.
2. Locate the test block via the criterion ID marker (the `# CRITERION-ID` (RSpec) or `// CRITERION-ID` (Go) comment placed
   by `/kaba:implement-tests`).
3. Read the criterion's behavior, related outcomes, and required variants from `ACCEPTANCE` to confirm what the test must verify.
4. Apply the recommended change from the finding's Recommendation column.
5. Log to the in-memory report with status FIXED, including:
   - Finding ID and criterion ID
   - File path and line number
   - Before code (the original test block)
   - After code (the modified test block)
   - What changed (one-line summary)

### 6. Resolve escalated findings interactively

For each escalated finding, present the human with full context in the conversation — one finding
at a time:

````
## Escalated Finding: [FindingID] — [CRITERION-ID]

**Criterion**: [CRITERION-ID] — "[full behavior, related outcomes, and required variants from acceptance-criteria.md]"

**Weakness**: [weakness description from test-review.md]

**Current implementation**: `[file:line]`
```[language]
[the actual test code block from the test file]
```

**Counterexample / evidence**: [passing incorrect implementation, rejected conforming implementation, or sourced gap evidence from test-review.md]

**Why escalated**: [specific reason — what makes this cross-file, uncertain, or multi-option]

**Options**:

| Option | Description | Trade-off |
|--------|-------------|-----------|
| A (Recommended) | [concrete fix description] | [what it affects, side effects if any] |
| B | [alternative fix] | [what it affects] |
| C | Leave as-is | [what risk is accepted by not fixing] |

You can pick an option, ask me questions about any of them, or describe your own approach.
````

**Interaction rules**:
- One finding at a time. Do not present the next finding until the current one is resolved.
- The human can ask clarifying questions before choosing (e.g., "what would option B look like
  exactly?", "would A break any other tests?"). Answer the question, then re-present the options.
- No pressure to commit — wait until the human picks an option or describes their own approach.
- Once resolved, apply the chosen fix immediately. Log to the in-memory report with status
  RESOLVED, including: the question asked, the human's choice, their rationale, and before/after
  code.
- **Out-of-plan existing tests need an allowlist entry with the approval.** When the chosen fix touches a pre-existing example not in the plan's allowlist, the human's approval authorizes exactly one machine append. Immediately before applying the fix, run from the repo root: `$(git config kaba.scriptdir)/snapshot-tests.sh allowlist-append --action TOUCH|MODIFY --id <exact example id> --landing <unchanged|failed|passed> --finding <FindingID>` — TOUCH when the example's status will not change (content-only edit), MODIFY (with the landing the human approved) when it will. The script resolves the identity from the baseline and stamps provenance; never edit test-plan.json or test-plan.md by hand. If the approved fix is REMOVE- or PIN-shaped, or implies the invalidation sweep missed further examples, do NOT append — that is a test-plan defect: STOP and emit implement-tests' escalation block.
- Log every append in the report (action, id, landing, finding).
- If the human says "skip" or "leave it", do NOT apply any change. Log as SKIPPED with the reason.

### 7. Re-validate

After all fixes (mechanical + resolved escalations) are applied:

1. **Snapshot capture**: Run `$(git config kaba.scriptdir)/snapshot-tests.sh capture post-test` from the
   repo root. This **overwrites** the existing post-test snapshot with the post-fix state. The
   chain stays clean: baseline → post-test (now updated) → post-impl later.
2. **Snapshot compare**: Run `$(git config kaba.scriptdir)/snapshot-tests.sh compare post-test` — the
   script resolves both snapshots and `test-plan.json` from the feature directory itself.
   Results must satisfy the approved schema-v3 action/landing contract. Ordinary new behavior
   tests remain failed; matched PIN/passed and conforming MODIFY/passed are legitimate green
   evidence, TOUCH preserves status, and REMOVE stays pending. Appended entries are printed under
   `ALLOWLIST` section — confirm the appended list matches exactly the
   approvals logged in this session, and carry it into the report.
3. **Banned pattern scan**: Run `$(git config kaba.scriptdir)/banned-patterns.sh` with the paths of all
   modified test files as positional arguments. If it reports FAIL, the fix introduced a banned
   pattern — rework the fix and re-run until PASS.

- **If snapshot compare FAILS**: Diagnose the reported violation using implement-tests step 7:
  unexpected status, unmatched PIN identity, digest drift, missing outcome, protected-file
  change, or plan-lock mismatch are different failures. Correct incorrect evidence or restore
  unauthorized edits; escalate a genuine plan defect. Never make already-conforming behavior
  fail artificially or weaken assertions to satisfy a landing. Re-capture/re-compare after fixes.
- **If banned patterns are found**: The fix introduced a banned pattern. Rework the fix to avoid
  the pattern. Re-scan. Repeat until PASS.

4. **Independent scoped re-review**: Collect criterion/source IDs from all FIXED or RESOLVED
   findings and record the exact changed paths plus any coverage/organization consequences.
   Do not re-review your own corrections or edit `test-review.md`. Write `test-fixes.md`, then
   direct the human to invoke `/kaba:review-tests <IDs>` in its isolated reviewer context. The
   fresh reviewer follows that skill's source/evidence checks and scoped finding merge, retaining
   unaffected findings and recomputing the full remaining verdict. If an upstream amendment
   changes broader coverage, request a full review instead. Until that review returns, report
   correction review as PENDING; passing mechanical gates alone does not establish readiness.
   If no findings were fixed, report SKIPPED and preserve the existing review.

### 8. Write report

Write the findings log to `FEATURE_DIR/test-fixes.md` using the Report Format below.

Print a summary to the conversation:

```
## Summary
- Findings processed: [N] / [N]
- Mechanical fixes applied: [N]
- Escalated and resolved: [N]
- Skipped: [N] (omit line if 0)
- Snapshot compare: PASS / FAIL
- Banned pattern scan: PASS / FAIL
- Independent re-review: PENDING / SKIPPED (no fixed criteria)
- Next step: [see guidance below]
```

**Next step guidance**:
- Corrections applied and gates passed: request `/kaba:review-tests <criterion/source IDs>` with
  independent context and scoped merge; report PENDING until reviewed. Broader upstream
  amendments require a full review.
- No corrections applied: preserve the findings and report the unresolved/skipped scope.
- Only after independent review may the human make the final go/no-go decision for Phase 3.
  This command never self-approves the corrected suite.

## Report Format

````markdown
# Test Fixes: [Feature Name]

**Feature**: [branch] | **Fixed**: [DATE] | **Review source**: test-review.md ([review DATE])

## Summary

- Findings processed: [N] / [N]
- Mechanical fixes applied: [N]
- Escalated and resolved: [N]
- Skipped: [N]

## Mechanical Fixes

### [FindingID] — [CRITERION-ID]: [short description]

**File**: `[test-file-path:line]`
**What changed**: [one-line summary of the change]

Before:
```
[original test block — use project's language]
```

After:
```
[modified test block]
```

(Repeat for each mechanical fix.)

## Resolved Escalations

### [FindingID] — [CRITERION-ID]: [short description]

**File**: `[test-file-path:line]`
**Why escalated**: [specific reason — cross-file, uncertain, multiple valid approaches]
**Question**: [the question posed to the human]
**Choice**: [which option the human picked, or "custom" with description]
**Rationale**: [why they picked it — from the conversation]
**Allowlist appended**: [none, or `TOUCH|MODIFY <id> → <landing> (finding <ID>)`]

Before:
```
[original code]
```

After:
```
[modified code]
```

(Repeat for each resolved escalation.)

## Skipped

(None, or list each skipped finding with the human's reason.)

## Validation

- Snapshot: post-test overwritten, compare vs baseline — PASS / FAIL
- Banned pattern scan — PASS / FAIL
````

## Key Rules

1. **Only test files.** Never write implementation code. Never modify non-test files except
   `test-fixes.md`. Use configured test permissions and runner inventory; explicit configurations have no `test_dir`.
2. **Scope and certainty determine classification.** Same-file + known fix = mechanical.
   Cross-file or uncertain = escalated. Severity is irrelevant to this classification.
3. **Every mechanical fix must be verifiable.** The before/after in `test-fixes.md` makes the
   change auditable.
4. **Escalated findings get full context.** Criterion text (from acceptance-criteria.md), weakness,
   current code with file:line, concrete counterexample/evidence, why escalated, options with trade-offs and
   recommendation. The human must be able to make an informed decision without looking anything up.
5. **Human can ask questions before choosing.** No pressure to commit — the agent answers
   follow-ups and re-presents options until the human decides.
6. **Overwrite post-test snapshot.** The post-fix state becomes the new post-test for the
   baseline → post-test → post-impl chain.
7. **Re-validate after all fixes.** Snapshot compare (approved action/landing contract) +
   `$(git config kaba.scriptdir)/banned-patterns.sh` + independent scoped re-review of fixed criteria/source obligations. Do not
   proceed with a failing gate.
8. **No automatic handoff; independent review first.** The human invokes isolated `/kaba:review-tests` for
   corrected scope; preserve unrelated findings. The author does not certify its own fixes or
   declare readiness. Human final acceptance remains required.
9. **GO verdict is a no-op, not an error.** Report and stop gracefully.
10. **Project rules violations in fixes are forbidden.** Any fix that would introduce a banned
    pattern is itself a bug — fix the fix.
11. **Gate exemptions: smallest unit, justified, or escalate.** Exemptions to any automated
    quality gate (N+1 detector, linter, type checker, and the like) MUST be scoped to the
    smallest unit that exhibits the justified pattern — a single test, line, or code path —
    never a whole file or directory. Every exemption MUST carry a documented justification
    at the exemption site. If the gate's tooling cannot express an exemption that narrow,
    escalate rather than widen.
12. **The plan's allowlist binds fixes too — and only `allowlist-append` may extend it.** Fixes may touch this feature's tests and allowlisted tests only. A human-approved escalated fix to an out-of-plan existing test appends its own TOUCH or MODIFY entry via `snapshot-tests.sh allowlist-append` (see step 6); the compare's plan-lock check rejects any other plan edit. REMOVE- and PIN-shaped needs, and anything suggesting the invalidation sweep was incomplete, remain test-plan defects: STOP and emit implement-tests' escalation block. REMOVE-marked (pending) tests stay pending — never resurrect or delete them here. Never edit test-plan.md or test-plan.json directly.

## Context

$ARGUMENTS
