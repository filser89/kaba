---
name: implement-tests
disable-model-invocation: true
description: Write all test code following the test plan. Only test files — no implementation code.
handoffs:
  - label: Review Tests
    agent: kaba:review-tests
    prompt: Review the implemented tests for quality and coverage
    send: true
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). The user may provide additional constraints, focus areas, or corrections to scope.

## Outline

1. Run `$(git config kaba.scriptdir)/resolve-feature.sh` from repo root. It prints three `KEY=value` lines — `REPO_ROOT`, `FEATURE_DIR`, `FEATURE_SPEC` — read them line-by-line (never `eval`; a path may contain spaces). For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

   - **Prior-run gate — resolve this BEFORE reading anything or arming the lock.** Step 3 changes repo state and runs the whole suite, so the gate has to come first. Run `$(git config kaba.scriptdir)/check-artifacts.sh implement-tests` from the repo root and read its `KEY=value` lines:
     - `PRIOR_RUN=yes` — STOP and ask the user: "`snapshots/post-test.json` already exists for this feature — a prior `/kaba:implement-tests` run completed and captured its post-test snapshot. Re-running rewrites the test session's work. Continue? The previous snapshot is not recoverable (feature artifacts are untracked at this stage)." Ask, then **end your turn** — do not answer yourself and do not proceed in the same response. Use `AskUserQuestion` if it is available. Continue only on an explicit yes.
     - `PRIOR_RUN=no` — proceed. This is the normal case for both a fresh start **and** a resume: the gate keys on `post-test.json`, which only exists after a completed run, never on `baseline.json`, which is present mid-session by design. The resume path in step 3 is unaffected.
     - `PRIOR_RUN=unknown`, a non-zero exit, or no `PRIOR_RUN=` line at all — STOP and report the script's stderr verbatim. **Absence of an answer is never "no."**

2. **Load context**:
   - **REQUIRED**: Read `FEATURE_DIR/test-plan.md` — the structural contract (files, describe blocks, criteria mapping, factories, helpers). If missing, ERROR and stop — suggest running `/kaba:plan-tests` first.
   - **REQUIRED**: Read `FEATURE_DIR/acceptance-criteria.md` — the behavioral contract (what each criterion asserts). If missing, ERROR and stop.
   - **REQUIRED**: Read `FEATURE_DIR/spec.md` — the feature spec (domain understanding). If missing, ERROR and stop.
   - Read `CLAUDE.md` for project conventions (test framework, banned patterns, style rules).
   - Read the project rules (CLAUDE.md/AGENTS.md, per `.kaba/config.yml`'s `rules_files`) for project-wide constraints.

3. **Arm the session lock, establish the baseline, validate the plan**:
   1. Run `$(git config kaba.scriptdir)/session-lock.sh set test` from repo root — this locks implementation code for the duration of the test session (enforced by the PreToolUse guard and the pre-commit hook).
   2. Run `$(git config kaba.scriptdir)/snapshot-tests.sh capture baseline` from repo root. The script decides fresh-start vs resume itself: with a clean test directory it (re)captures; with in-progress test work it refuses to overwrite an existing baseline and keeps it — recapturing over half-written tests would absorb them into the baseline and silently exempt them from the new-test gate.
   3. Run `$(git config kaba.scriptdir)/snapshot-tests.sh validate-plan` from repo root. This checks every entry of `FEATURE_DIR/test-plan.json` (schema v2) against the baseline: identity exists, description matches byte-for-byte. If it FAILS, the plan is stale relative to reality — STOP and emit the test-plan defect escalation (see Escalation below) with the validator's per-entry errors. Do not write any test code past a failed validation.

4. **Survey existing test infrastructure**:
   - The test directory is `test_dir` in `.kaba/config.yml` — read it from there; never infer it from project structure.
   - Read test helper and configuration files (e.g., `rails_helper.rb`, `spec_helper.rb`, `conftest.py`, `jest.config.*`).
   - Read all existing support/helper files for patterns to follow (require statements, module inclusion, configuration conventions).
   - Note existing factories/fixtures.
   - Note existing shared helpers and reusable modules.

5. **Create or update support files** — build in dependency order so test files can use them:
   1. **Shared helpers**: For each helper in test-plan.md's Shared Helpers section:
      - **NEW**: Create the file, following the specified interface and matching existing support file patterns.
      - **MODIFY**: Read the existing file first. Add the new interface without breaking existing functionality.
      - **EXISTS**: Do not touch. Already has what's needed.
   2. **Factories/fixtures**: For each factory in test-plan.md's Factories section:
      - **NEW**: Create the file with the specified base attributes, traits/variants, and associations.
      - **MODIFY**: Read the existing file first. Add new traits/variants or adjust attributes as specified. Do not remove or rename existing traits unless the test plan explicitly says to.
      - **EXISTS**: Do not touch.

6. **Implement test files** — work through every test file listed in test-plan.md's Test Files section:
   - **Order**: Foundations first (model/unit tests), then integration/request tests, then cross-cutting tests. Follow the dependency graph implied by the test plan.
   - **For each NEW file**:
     - Create the describe/context/it block hierarchy matching test-plan.md's Describe Blocks exactly.
     - Write test blocks with descriptive names derived from the acceptance criteria.
     - Each test block must contain a real assertion that exercises the criterion's behavior.
   - **For each MODIFY file**:
     - Read the existing file first to understand its current structure.
     - Add new describe/context/it blocks as specified in test-plan.md's Describe Blocks for this file.
     - Renaming an existing block is allowed only when the plan's Planned State Changes declares it. Removing or reordering existing blocks is NEVER allowed in-session — removal has its own lane (REMOVE entries, below), and reordering breaks the positional identities the whole gate rests on.
     - Add new blocks APPENDED after existing siblings — never inserted before or between them. Appending preserves every existing test's address; insertion shifts them and will fail the compare loudly.
     - Integrate new blocks into the existing hierarchy — match the file's current style and conventions.
   - **For each REMOVE entry in the plan's Planned State Changes**: do not delete the test. Mark it skipped with the removal marker, using the project's framework idiom (per CLAUDE.md), carrying the feature name — e.g. for RSpec: `it "original description", skip: "REMOVED by 004-feature-name" do`. The test must report as pending at post-test.
   - **For all test files**: Tests MUST fail because implementation is missing (correct failure), not because of syntax errors or misconfigured support files (incorrect failure).
   - **Tests must register even though the implementation does not exist yet**: do not reference a not-yet-defined implementation symbol where the framework resolves it at file-load / collection time (e.g. a class named in a test-group header, or a top-of-file import of the unbuilt module). That aborts loading and registers zero tests for the file — the snapshot/compare gate then silently passes on nothing (the capture step hard-fails on such load/collection errors). Reference implementation lazily instead — inside test bodies, or via factories/fixtures — so every test registers and fails at **run** time for the right reason. Follow the project's test conventions (CLAUDE.md) for the framework-specific idiom that achieves this.
   - **After each file**: Report which file was created or modified and how many criteria it covers.

7. **Snapshot post-test and compare**:
   1. Run `$(git config kaba.scriptdir)/snapshot-tests.sh capture post-test`
   2. Run `$(git config kaba.scriptdir)/snapshot-tests.sh compare post-test` — the script resolves both snapshots and `test-plan.json` from the feature directory itself and dies if the plan file is missing or not schema v2.
   - **If compare FAILS**, diagnose by violation type:
     - New test not failed → assertions are trivially true (or a REMOVE marker landed on the wrong test). Fix the assertions so they exercise real behavior.
     - Changed test not in the allowlist → either support files broke existing test setup (fix without altering existing behavior), or the plan is missing an entry — that is a test-plan defect: STOP and escalate (see Escalation below). Never "fix" this by touching test-plan.json.
     - Allowlisted MODIFY not landing on failed → the modification asserts already-existing behavior or went to pending. Strengthen the assertion; transitions to pending are never excused for MODIFY.
     - REMOVE entry not pending → the removal marker is missing or on the wrong test.
     - Unexpected removals → an existing test was deleted or blocks were reordered. Restore from version control; removal is never done by deletion in-session.
     - Re-capture post-test and re-compare after fixes. Repeat until PASS.
   - The compare also prints WARNINGS for unused MODIFY entries (planned change that never happened). Warnings do not fail the gate — carry them into the completion report for the human review.

8. **Test quality check**: Run `$(git config kaba.scriptdir)/banned-patterns.sh` from repo root. If it reports FAIL, fix the violations and re-run until PASS.

9. **Completion report**:

   ```
   ## Summary
   - Test files: [N] new, [N] modified, [N] existing (of [N] total in plan)
   - Factories: [N] new, [N] modified, [N] existing (of [N] total in plan)
   - Shared helpers: [N] new, [N] modified, [N] existing (of [N] total in plan)
   - Criteria covered: [N] / [N] (MUST equal test-plan total — if not, ERROR)
   - Snapshot comparison: PASS / FAIL
   - Allowlist warnings: [list of unused MODIFY entries, or "none"]
   - Quality check: PASS / FAIL
   ```

   If ANY check is FAIL or criteria count does not match, do NOT proceed. Fix and re-validate.

## Escalation — test-plan defect

If a criterion cannot be satisfied within the plan's Planned State Changes — an existing test not in the allowlist must change, a planned entry points at the wrong test, an unforeseen removal surfaces — or validate-plan fails, STOP. Never modify an out-of-plan test, never touch `test-plan.md` or `test-plan.json`, never do the work and annotate it. Output:

```
## ESCALATION — test-plan defect

- **Criterion**: [ID + short description] (omit if from validate-plan)
- **Requires**: [MODIFY | REMOVE] of [identity — description] — not in the allowlist
  (or: [validator's per-entry errors])
- **Conflict**: [why the criterion cannot be met within the current plan]
- **Amendment needed**: [new entry / corrected entry / structural re-plan]
```

The human re-runs `/kaba:plan-tests` with this block as input; it regenerates the plan and `test-plan.json` whole. Then re-run this command — it resumes idempotently (the baseline is preserved automatically while test work is in progress).

## Key Rules

1. **Only test files.** Do NOT create models, controllers, routes, migrations, or any implementation code. Tests should fail because the implementation is missing — that's correct.
2. **Follow the test plan exactly.** File paths, describe-block hierarchy, criterion mapping, factory names — all frozen by test-plan.md. Do not reorganize, rename, or add structure beyond what the plan specifies.
3. **Every criterion gets a test.** Each criterion ID from the Criteria Mapping table must appear as a tested behavior. No criterion may be skipped.
4. **Tests must fail for the right reason.** Missing implementation is a correct failure. Syntax errors, factory misconfiguration, or missing requires are incorrect failures. Run the test suite periodically during implementation to catch setup errors early.
5. **No banned patterns.** `$(git config kaba.scriptdir)/banned-patterns.sh` codifies the greppable banned patterns from the project rules. Private method testing is also banned but requires judgment — it cannot be detected mechanically.
6. **Respect existing infrastructure.** Do not modify existing test configuration or support files. Add new files; don't overwrite existing ones.
7. **The test plan is a contract, and its allowlist is the gate's input.** If the plan has errors or gaps, STOP and emit the test-plan defect escalation — do not silently deviate, and never edit test-plan.md or test-plan.json from this session. Re-planning belongs to `/kaba:plan-tests`.
8. **Tests must register before the implementation exists.** Don't let a test file fail to load/collect by referencing a not-yet-defined symbol at load time (a class in a group header, a top-of-file import). Reference implementation lazily so each test registers and fails at run time. See CLAUDE.md for the project's framework-specific idiom.
9. **Gate exemptions: smallest unit, justified, or escalate.** Exemptions to any automated quality gate (N+1 detector, linter, type checker, and the like) MUST be scoped to the smallest unit that exhibits the justified pattern — a single test, line, or code path — never a whole file or directory. Every exemption MUST carry a documented justification at the exemption site. If the gate's tooling cannot express an exemption that narrow, escalate rather than widen.
10. **Existing tests: append, rename only as planned, never delete or reorder.** New blocks go after existing siblings. REMOVE entries are skip-marked, not deleted — deletion belongs to the post-feature cleanup script, never to this session. Violations don't corrupt the gate — they fail it loudly; fix by restoring the file, never by adjusting the plan.
