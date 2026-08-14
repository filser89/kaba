# TDD-First Workflow for AI Coding Agents

This is kaba's workflow documentation — the pipeline the plugin's commands implement, and the
reasoning behind it. For installation and command-by-command usage, see the repo
[README](../README.md).

### Core Insight

Standard AI coding agents don't do TDD. When told "use TDD," they write code first, then tests. Prompts are suggestions — agents drift from them.

**Enforce workflow constraints with validation hooks (commands that return pass/fail), not prompts.** If you can express a rule as a command, don't express it as a prompt.

### Key Advantages

1. **Tests are easier to review than code** — especially with shoulda syntax (reads like English). If the tests are correct, the implementation is reviewable by the test suite itself.
2. **Hooks can't be ignored** — a git pre-commit hook that rejects changes to the test directory during implementation is a guarantee, not a suggestion.
3. **Test snapshots catch regressions** — by recording which tests are red/green before and after each session, you detect unintended side effects automatically.
4. **Separation of concerns** — the agent can't write tests that are biased toward its own implementation because it hasn't written the implementation yet.
5. **Existing tooling handles code quality** — the project's own linter and any suite-embedded checks (e.g. N+1 detection) are pass/fail commands. No need to prompt for these.

### Two-Session Architecture

Instead of forcing one-test-at-a-time (which kills the speed advantage of agents), the work splits into two isolated sessions:

- **Session 1 (Test Session)**: Agent writes all tests based on acceptance criteria. Human reviews. No implementation code.
- **Session 2 (Implementation Session)**: Agent writes implementation to make tests green. Cannot touch test files. Validated by hooks.

The agent does the typing. The human does the thinking (what to test, what the contracts are).

### The Full Workflow

#### Phase 0: Project Setup (once)

| Step | Command / Action | Purpose | Output |
|------|------------------|---------|--------|
| 1 | Maintain project rules | Project-wide principles, tech stack, non-negotiables | `CLAUDE.md` / `AGENTS.md` |
| 2 | `/kaba:architecture` | Full codebase scan — current-state patterns that later commands trust | `.kaba/architecture.md` |

#### Phase 1: Specification (human-controlled)

| Step | Command | Purpose | Output |
|------|---------|---------|--------|
| 3 | `/kaba:specify` | Feature specification — user stories, acceptance scenarios, requirements | `FEATURE_DIR/spec.md` |
| 4 | `/kaba:clarify` | *(optional)* Catch gaps before moving forward | Updates `spec.md` |

#### Phase 2: Test Session

| Step | Command / Action | Purpose | Output |
|------|-----------------|---------|--------|
| 5 | `/kaba:acceptance-criteria` | Decompose spec into granular, test-oriented criteria | `FEATURE_DIR/acceptance-criteria.md` |
| 6 | `/kaba:plan-tests` | Plan test organization — files, factories, helpers, criterion mapping, state-change allowlist. Also serves as the task list for implement-tests (no separate tasks step needed). | `FEATURE_DIR/test-plan.md` + `test-plan.json` |
| 7 | Snapshot: capture baseline | Run test suite, save state to file | `FEATURE_DIR/snapshots/baseline.json` |
| 8 | `/kaba:implement-tests` | Agent writes all test code following the test plan. Only test files. | Test files in the configured test directory |
| 9 | Snapshot: capture post-test | Run test suite, save state to file | `FEATURE_DIR/snapshots/post-test.json` |
| 10 | Snapshot: compare | Compare post-test vs baseline (see Snapshot Comparison Rules) | Pass/fail report |
| 11 | Hook: test quality | Automated check — reject if specs use `receive`, `expect_any_instance_of`, `respond_to`, or test private methods | Pass/fail |
| 12 | `/kaba:review-tests` | Agent review — "could a terrible implementation pass these tests?" | Structured findings report |
| 13 | `/kaba:fix-tests` | *(optional — only on a NO-GO verdict)* Apply the review findings to the test files — mechanical fixes directly, escalated findings resolved with the human — then re-validate (snapshot + banned-pattern scan) | Updated test files + `FEATURE_DIR/test-fixes.md` |
| 14 | Human review | Review test descriptions and agent findings. Final go/no-go. | Go/no-go |

#### Phase 3: Implementation Session

| Step | Command / Action | Purpose | Output |
|------|-----------------|---------|--------|
| 15 | `/kaba:plan-code` | Plan implementation informed by the locked tests — components, schema, decisions, build order | `FEATURE_DIR/code-plan.md` |
| 16 | `/kaba:implement-code` | Agent writes code to make tests green. Cannot touch the test directory. | Implementation files |
| 17 | Snapshot: capture post-impl | Run test suite, save state to file | `FEATURE_DIR/snapshots/post-impl.json` |
| 18 | Snapshot: compare | Compare post-impl vs post-test (see Snapshot Comparison Rules) | Pass/fail report |
| 19 | Gate: linter | The project's configured linter (`linter_command`) must pass; any suite-embedded checks (e.g. N+1 detection) ride along for free inside the same green `test_command` run | Pass/fail |

Steps 17–19 run **inline inside `/kaba:implement-code`** as end gates (same pattern as implement-tests owning its snapshot steps), plus a fourth inline gate: the test directory must be untouched per version control — it catches in-place test edits the snapshot compare cannot see (a tampered test transitions `failed→passed`, exactly what the compare expects).

#### Phase 4: Completion

| Step | Command / Action | Purpose | Output |
|------|-----------------|---------|--------|
| 20 | `/kaba:architecture-diff` | Fold this feature's architectural delta into the doc | Updates `.kaba/architecture.md` |
| 21 | Script: `$(git config kaba.scriptdir)/cleanup-tests.sh` | *(optional — only when the feature had REMOVE entries)* Delete tests skip-marked REMOVED by the feature; self-verifying with rollback; human reviews the deletion diff | Updated test files |

#### Outside the pipeline: `/kaba:research`

`/kaba:research` is deliberately **not** a step in this workflow. It is an optional, human-triggered decision-support command: when the human needs more information to make a decision — at any phase — it investigates one open question for the current feature and appends a recommendation to `FEATURE_DIR/research-log.md`. Its output informs the human only; no workflow command reads it.

### Snapshot Comparison Rules

Snapshots record the state (passed/failed/pending) of every test example in the suite. Capture and compare are **separate operations**: capture runs the test suite and saves to a named JSON file; compare takes two snapshot files and reports pass/fail. Three snapshots are captured per feature, with two comparisons.

#### Post-Test Session (snapshot 2 vs baseline)

| Test Category | Expected State | Violation Means |
|---------------|---------------|-----------------|
| New tests (from this feature) | Red (failed) | Implementation leaked into test session |
| MODIFY-allowlisted tests | Red (failed) — or unchanged | Modification asserts already-existing behavior, or went to pending |
| REMOVE-allowlisted tests | Pending (skip-marked) | Planned removal not executed |
| All other previously green tests | Green (passed) | Unintended regression |
| All other previously red tests | Red (failed) | Accidental fix or interference |
| Any test, removed from the suite | Never | In-session deletion — removals are skip-marked, deleted post-feature |
| Any test → pending, unallowlisted | Never | A test was switched off without a REMOVE entry |

The allowlist is `FEATURE_DIR/test-plan.json` (schema v2): per-test addresses + verified descriptions, generated whole by `plan-tests` from the plan's Planned State Changes table and validated against the baseline at session start (`validate-plan`). A group address covers every example under it. Unused MODIFY entries surface as compare warnings for the human review; an unexecuted REMOVE is a violation.

#### Post-Implementation (snapshot 3 vs post-test)

| Test Category | Expected State | Violation Means |
|---------------|---------------|-----------------|
| New tests (from this feature) | Green (passed) | Implementation incomplete |
| Modified tests (from this feature) | Green (passed) | Implementation incomplete |
| All other previously green tests | Green (passed) | Unintended regression |
| All other previously red tests | Red (failed) | Accidental fix or interference |

### Snapshot Script Invocation Map

The snapshot script (`$(git config kaba.scriptdir)/snapshot-tests.sh`) is called inline by commands, same as `resolve-feature.sh`. No Claude Code hooks needed.

| Script call | Command | When |
|---|---|---|
| `identities` | `/kaba:plan-tests` | Survey — dry-run identity listing; sole source for allowlist addresses and descriptions |
| `capture baseline` | `/kaba:implement-tests` | Beginning — refuses to overwrite the baseline while test work is in progress (resume mode) |
| `validate-plan` | `/kaba:implement-tests` | Beginning — `test-plan.json` (v2) checked against the baseline, before any test code |
| `capture post-test` | `/kaba:implement-tests`; `/kaba:fix-tests` (overwrite) | End — after all test code is written / after fixes |
| `compare post-test` | `/kaba:implement-tests`; `/kaba:fix-tests` | End — immediately after post-test capture; snapshots and allowlist resolved from the feature dir |
| `capture post-impl` | `/kaba:implement-code` | End — after all implementation code is written |
| `compare post-impl` | `/kaba:implement-code` | End — immediately after post-impl capture |
| `cleanup-tests.sh` (own script) | Human-triggered, between features | Deletes skip-marked REMOVED tests; self-verifying with rollback |

### What Gets Enforced by Hooks vs. Prompts

| Concern | Enforcement | Mechanism |
|---------|-------------|-----------|
| No implementation code in test session | Hook | Session lock (`test` mode): PreToolUse guard blocks agent edits to implementation paths in real time; pre-commit rejects staged implementation paths |
| No test changes in implementation session | Hook | Session lock (`implement` mode): PreToolUse guard blocks agent edits to the test directory in real time; pre-commit rejects staged test paths; test-directory-untouched end gate in `implement-code` |
| No `receive`/`expect_any_instance_of`/`respond_to` in specs | Script | `$(git config kaba.scriptdir)/banned-patterns.sh`, pass/fail |
| Snapshot comparison rules | Hook | Snapshot diff script, pass/fail |
| Linter compliance | Hook | The project's configured `linter_command` (`.kaba/config.yml`), pass/fail |
| N+1 query detection (if the suite has it, e.g. Prosopite) | Hook | Rides along inside the `test_command` green run, pass/fail |
| Test plan criterion coverage | Prompt | Agent follows test plan structure |
| Code architecture decisions | Prompt | Agent follows implementation plan |

### Session Lock

The two-session boundary is enforced by a lock with one state file and one rule engine, consumed by two hooks:

- **State**: `.kaba/session-lock` (git-ignored) holds `test` or `implement`; absent = unrestricted. `/kaba:implement-tests` sets `test` at its start; `/kaba:implement-code` sets `implement` at its start and clears the lock after all end gates pass — a completed feature leaves the repo unrestricted, so the lock is armed only between the test session and the end of the implementation session. Manual override: `$(git config kaba.scriptdir)/session-lock.sh status|clear`.
- **Rules** (complement of `test_dir`, derived from `.kaba/config.yml`, in `session-lock.sh check`): `implement` may write everything **except** `test_dir`; `test` may write **only** `test_dir`, `feature_dir`, and the configured `test_writable` carve-outs. The rule is a complement, not a hand-maintained deny-list of implementation territory — nothing project-specific needs to be kept in sync as the codebase grows.
- **PreToolUse guard** (`hooks/hooks.json`, self-registered by the plugin — no `settings.json` edit needed): blocks the agent's `Write`/`Edit`/`NotebookEdit` calls to locked paths at the moment of the edit, giving real-time feedback on path-declaring tool calls.
- **Pre-commit hook** (`.kaba/hooks/pre-commit`, installed into the consumer repo by `/kaba:init`): validates staged paths at the commit boundary via `core.hooksPath`. (`--no-verify` can bypass — guardrail, not security.)

The **guarantee** is the pair of git-based checks — the pre-commit hook and the implementation session's end gates. They inspect the working tree and the index, so they are indifferent to how a change arrived. The PreToolUse guard is real-time feedback layered on top of them, not a substitute.
