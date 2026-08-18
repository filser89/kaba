---
name: implement-code
disable-model-invocation: true
description: Write implementation code to make the locked test suite green, following code-plan.md. Only implementation files — never test files.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). The user may provide additional constraints, focus areas, or corrections to scope.

## Outline

1. **Resolve feature paths, then check for a prior run**: Run `$(git config kaba.scriptdir)/resolve-feature.sh` from the repo root. It prints three `KEY=value` lines — `REPO_ROOT`, `FEATURE_DIR`, `FEATURE_SPEC` — read them line-by-line (never `eval`; a path may contain spaces).
   - **Prior-run gate — resolve this BEFORE reading anything or arming the lock.** Step 2 changes repo state, so the gate has to come first. Run `$(git config kaba.scriptdir)/check-artifacts.sh implement-code` from the repo root and read its `KEY=value` lines:
     - `PRIOR_RUN=yes` — STOP and ask the user: "`snapshots/post-impl.json` already exists for this feature — a prior `/kaba:implement-code` run completed and passed its end gates. Re-running rewrites the implementation session's work. Continue? The previous snapshot is not recoverable (feature artifacts are untracked at this stage)." Ask, then **end your turn** — do not answer yourself and do not proceed in the same response. Use `AskUserQuestion` if it is available. Continue only on an explicit yes.
     - `PRIOR_RUN=no` — proceed. This is the normal case for both a fresh start and the idempotent re-run described in Key Rule 2: `post-impl.json` is written only after all end gates pass, so a session that stopped short leaves the gate open.
     - `PRIOR_RUN=unknown`, a non-zero exit, or no `PRIOR_RUN=` line at all — STOP and report the script's stderr verbatim. **Absence of an answer is never "no."**

2. **Arm the session lock**: Run `$(git config kaba.scriptdir)/session-lock.sh set implement` from the repo root. This locks the test directory for the duration of the implementation session (enforced by the PreToolUse guard and the pre-commit hook).

3. **Load context**:
   - **REQUIRED**: Read `FEATURE_DIR/code-plan.md` — the implementation contract (components with action→test-group mapping, data model, decision verdicts, build order). If missing, ERROR and stop — suggest running `/kaba:plan-code` first.
   - **REQUIRED**: Verify `FEATURE_DIR/snapshots/post-test.json` exists — the locked-suite snapshot this session is graded against. If missing, ERROR and stop — the test session is incomplete.
   - Read `CLAUDE.md` for project conventions — this is where the framework specifics live: the test directory, the test runner, the linter, the generator tooling and how to disable its test scaffolding, style rules.
   - Read the project rules (CLAUDE.md/AGENTS.md, per `.kaba/config.yml`'s `rules_files`) for project-wide constraints.
   - Read `.kaba/architecture.md` for the existing patterns the code must stay consistent with.
   - The test directory is `test_dir` in `.kaba/config.yml` — read it from there; never infer it from project structure.
   - Do **NOT** read `spec.md`, `acceptance-criteria.md`, or `test-plan.md` — their content is absorbed into the plan and the locked tests. The plan says what to build; the tests referee it. Test files are read per build-order step as needed.

4. **Survey the existing codebase**: Read the project manifest and configuration, and the existing implementation directories, for patterns to follow (naming, base classes, module conventions). The plan's components follow `architecture.md`; the code must match how the project actually does things.

5. **Execute the Build Order, step by step** — the Build Order in `code-plan.md` is the task list. For each step, in order:
   - Re-read the step's entry in the plan's Components section: its responsibility, the test groups it greens, its collaborators, and any Decision verdicts that constrain it. Read the test files it claims to green — they are the precise behavioral contract.
   - **Use the project's generators** where one exists for what's being created (per project conventions), **with any test-file scaffolding disabled** — a generator must never create or modify files in the test directory. Generated test files would violate the session lock, conflict with the locked suite, and fail the post-impl compare as "new test added". The framework-specific flag comes from project conventions.
   - **Apply schema changes** through the project's standard mechanism (per conventions), ensuring the test environment sees them before tests run.
   - **Run the test files this step claims to green** using the project's test runner. Iterate until they pass. Earlier steps' tests must stay green; a wrong turn surfaces here, not after the last step.
   - **After each step**: Report which files were created or modified and which test groups went green.

6. **End gates** — run in order; ALL must PASS:
   1. **Snapshot capture**: Run `$(git config kaba.scriptdir)/snapshot-tests.sh capture post-impl` from the repo root. The capture aborts loudly on load errors — fix those first (they mean broken code, not missing implementation).
   2. **Snapshot compare**: Run `$(git config kaba.scriptdir)/snapshot-tests.sh compare post-impl` — the script resolves both snapshot paths from the feature directory itself.
   3. **Test directory untouched**: The working tree under the test directory must be clean per version control (`git status --porcelain -- <test-dir>` prints nothing). This catches in-place test edits the compare cannot see, and untracked files.
   4. **Linter**: Run the project's linter (per conventions); it must pass. Quality checks that run inside the test suite (e.g. N+1 detection) have already ridden along with the green run.
   - **If a gate FAILS**, diagnose by violation type:
     - Feature tests still red → implementation incomplete. Continue iterating within the plan (see Key Rule 2), or escalate if the plan itself is the obstacle (step 7).
     - Regression (a previously passing test now fails) → this feature's code broke existing behavior. Fix without altering any existing behavioral contract.
     - "New test added" / "test was removed" / test directory dirty → the test directory was touched. Restore it from version control; never "fix" this by adjusting tests.
     - Linter offenses → fix the style violations; they never justify touching a test or deviating from the plan.
   - Re-capture, re-compare, and re-run gates after fixes. Repeat until all PASS — or stop with an escalation.

7. **Escalation — plan defect (rare)**: If a test group cannot go green within the plan's components, schema, and decision verdicts, the plan is defective. STOP — do not improvise architecture, do not silently deviate, do not edit `code-plan.md`, and never touch a test. Output:

   ```
   ## ESCALATION — plan defect

   - **Failing test group**: [test file / group name] ([criterion IDs])
   - **Plan prescribes**: [the component / schema element / decision verdict in conflict]
   - **Conflict**: [why the prescription cannot satisfy the test]
   - **Re-plan needed**: [what kind — component structure / schema / decision]
   ```

   The human re-runs `/kaba:plan-code` (or amends the plan) and then re-runs this command. Re-runs are idempotent: for each build-order step whose test groups already pass, verify and skip.

8. **Disarm the session lock**: Run `$(git config kaba.scriptdir)/session-lock.sh clear` from the repo root. All end gates have passed, so the two-session boundary for this feature is complete — the repo returns to unrestricted until the next test session arms the lock. A session that stops on a failed gate or an escalation (step 7) never reaches this step; the lock stays armed.

9. **Completion report**:

   ```
   ## Summary
   - Build order: [N] / [N] steps completed
   - Suite: [G] green / [T] total ([R] were red at post-test)
   - Snapshot compare (post-impl): PASS / FAIL
   - Test directory untouched: PASS / FAIL
   - Linter: PASS / FAIL
   ```

   If ANY gate is FAIL, do NOT report completion. Fix and re-validate, or escalate (step 7).

## Key Rules

1. **Only implementation files — never the test directory.** The session lock enforces this mechanically; the compare and the test-directory-untouched gate verify it. Tests going green must come from implementation, nothing else.
2. **The plan is a contract.** Components, schema, decision verdicts, and build order are fixed by `code-plan.md`. Below the plan's altitude — method bodies, private decomposition, helper internals — is this command's own territory: iterate there freely.
3. **Escalate plan defects; never improvise architecture.** If a test cannot go green within the plan, the plan is broken — stop and report (Outline step 7). Silent deviation is forbidden. Re-planning belongs to `/kaba:plan-code`.
4. **Green for the right reason.** Never weaken, skip, disable, or delete a test to pass a gate. A gate that can only pass by touching a test is an escalation, not a workaround.
5. **Generators must never touch the test directory.** Use the project's generators for what they cover (per conventions), always with test scaffolding disabled.
6. **Framework specifics come from project conventions, never from this command.** Test directory, test runner, and linter come from `.kaba/config.yml` (`test_dir`, `test_command`, `linter_command`); generator flags are resolved from CLAUDE.md and project structure at runtime.
7. **Respect existing code.** Follow `architecture.md` and the patterns the codebase actually uses. Do not refactor existing code beyond what the plan calls for.
8. **Never commit.** Finishing the work and committing it are separate; the human decides when to commit.
9. **All gates must PASS before reporting done.** No partial-success completion reports.
10. **Gate exemptions: smallest unit, justified, or escalate.** Exemptions to any automated quality gate (N+1 detector, linter, type checker, and the like) MUST be scoped to the smallest unit that exhibits the justified pattern — a single test, line, or code path — never a whole file or directory. Every exemption MUST carry a documented justification at the exemption site. If the gate's tooling cannot express an exemption that narrow, escalate rather than widen.

## Next Step

Once every end gate has passed and the session lock is clear, the next step is
`/kaba:architecture-diff`, which folds this feature's architectural delta into
`.kaba/architecture.md`. It is mandatory at the end of every feature — report it as the next step,
not as an optional extra.
