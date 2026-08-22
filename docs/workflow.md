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

Steps 17–19 run **inline inside `/kaba:implement-code`** as end gates (same pattern as implement-tests owning its snapshot steps), plus a fourth inline gate: the test directory must be untouched per version control. That remains defense in depth behind digest comparison, including examples whose digest cannot be resolved.

#### Phase 4: Completion

| Step | Command / Action | Purpose | Output |
|------|-----------------|---------|--------|
| 20 | `/kaba:architecture-diff` | Fold this feature's architectural delta into the doc | Updates `.kaba/architecture.md` |
| 21 | Script: `$(git config kaba.scriptdir)/cleanup-tests.sh` | *(optional — only when the feature had REMOVE entries)* Delete tests skip-marked REMOVED by the feature; self-verifying with rollback; human reviews the deletion diff | Updated test files |

#### Outside the pipeline: `/kaba:research`

`/kaba:research` is deliberately **not** a step in this workflow. It is an optional, human-triggered decision-support command: when the human needs more information to make a decision — at any phase — it investigates one open question for the current feature and appends a recommendation to `FEATURE_DIR/research-log.md`. Its output informs the human only; no workflow command reads it.

### Snapshot Comparison Rules

Snapshots record the state (passed/failed/pending) and a formatting-insensitive structural digest of every resolvable test example in the suite. Capture and compare are **separate operations**: capture runs the test suite and saves to a named JSON file; compare takes two snapshot files and reports pass/fail. Three snapshots are captured per feature, with two comparisons.

#### Post-Test Session (snapshot 2 vs baseline)

| Test Category | Expected State | Violation Means |
|---------------|---------------|-----------------|
| New tests, not PIN-allowlisted | Red (failed) | Implementation leaked into test session |
| PIN-allowlisted new tests | Green (passed) | Behavior expected to conform does not, or the planned description drifted |
| MODIFY-allowlisted tests | Entry's expected landing (`failed` or `passed`) | Modification landed on the wrong state |
| REMOVE-allowlisted tests | Pending (skip-marked) | Planned removal not executed |
| TOUCH-allowlisted tests | Same status, changed structural digest | Planned content edit did not occur, or changed status |
| Other existing test content | Same structural digest when available | Unplanned test-body edit |
| All other previously green tests | Green (passed) | Unintended regression |
| All other previously red tests | Red (failed) | Accidental fix or interference |
| Any test, removed from the suite | Never | In-session deletion — removals are skip-marked, deleted post-feature |
| Any test → pending, unallowlisted | Never | A test was switched off without a REMOVE entry |

The allowlist is `FEATURE_DIR/test-plan.json` (schema v3): `{action, expected_landing}` entries over MODIFY/REMOVE/PIN/TOUCH. `plan-tests` generates it whole from the Planned State Changes table; `validate-plan` checks it against the baseline and writes `snapshots/test-plan.lock.json`. A group address covers every example under it for id-based actions; PIN matches an exact file + planned full description. During fix-tests, a human-approved escalation may add only a provenance-stamped TOUCH or MODIFY through `allowlist-append`; compare rejects every other in-session plan edit. Unused MODIFY/TOUCH and unfulfilled PIN entries surface as warnings; an unexecuted REMOVE is a violation.

#### Post-Implementation (snapshot 3 vs post-test)

| Test Category | Expected State | Violation Means |
|---------------|---------------|-----------------|
| New tests (from this feature) | Green (passed) | Implementation incomplete |
| Modified tests (from this feature) | Green (passed) | Implementation incomplete |
| All other previously green tests | Green (passed) | Unintended regression |
| All other previously red tests | Red (failed) | Accidental fix or interference |
| Existing test content | Unchanged structural digest when available | Test edited during implementation |

### Snapshot Script Invocation Map

The snapshot script (`$(git config kaba.scriptdir)/snapshot-tests.sh`) is called inline by commands, same as `resolve-feature.sh`. No Claude Code hooks needed.

| Script call | Command | When |
|---|---|---|
| `identities` | `/kaba:plan-tests` | Survey — dry-run identity listing; sole source for allowlist addresses and descriptions |
| `capture baseline` | `/kaba:implement-tests` | Beginning — refuses to overwrite the baseline while test work is in progress (resume mode) |
| `validate-plan` | `/kaba:implement-tests` | Beginning — `test-plan.json` (v3) checked against the baseline and locked, before any test code |
| `allowlist-append` | `/kaba:fix-tests` | During a human-approved escalation — append one provenance-stamped TOUCH/MODIFY entry resolved from the baseline |
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
| Re-run overwrite confirmation | Prompt | `check-artifacts.sh` answers *has this step already completed?*; the command's own step 1 acts on the answer (see **Re-running a step**) |

The overwrite confirmation is the one rule in this table that is prompt-held by necessity rather than
by choice. Nothing can force the agent to *run* the script, and a `PreToolUse` hook — the mechanism
used for everything else — fires at write time, which is far too late: the cost being prevented is a
whole regeneration's worth of analysis, spent before a single byte is written.

### Re-running a step

Feature artifacts under `feature_dir` are untracked until late in the pipeline, so a second run of a
command that has already completed destroys the first version with no git copy to restore. Six
commands therefore check before doing anything else, via
`$(git config kaba.scriptdir)/check-artifacts.sh <command>`:

| Command | What proves a prior run |
|---|---|
| `/kaba:specify` | a feature branch resolved at all — see below |
| `/kaba:acceptance-criteria` | `acceptance-criteria.md` |
| `/kaba:plan-tests` | `test-plan.md`, `test-plan.json` |
| `/kaba:plan-code` | `code-plan.md` |
| `/kaba:implement-tests` | `snapshots/post-test.json` |
| `/kaba:implement-code` | `snapshots/post-impl.json` |

Three properties are load-bearing and should not be "simplified" later:

- **The gate keys on completion markers, never on in-progress state.** `implement-tests` checks
  `post-test.json`, *not* `baseline.json` — `baseline.json` exists mid-session by design, and the
  resume path depends on it (snapshot capture refuses to overwrite a baseline while test work is in
  progress). Switching the gate to `baseline.json` would make every resume ask, defeating that path.
- **`specify` gates on branch resolution, not on `spec.md`.** It never overwrites anything;
  `new-feature.sh` allocates the *next* number and branches off whatever is checked out, so the
  hazard is a stray feature hanging off the current one. Gating on the file would sail past the
  ordinary interrupted case — branch and directory created, spec never written.
- **No answer is not the same as "no."** If the script exits non-zero or prints no `PRIOR_RUN=` line,
  the command stops. Otherwise a missing or unreachable script — the exact thing a stale
  `kaba.scriptdir` produces — would read as "no prior run" and sail straight through the gate.

`/kaba:clarify` is the deliberate exception: re-running it is a legitimate way to resolve something
still unclear, so it does not gate on its output existing. It asks only when the spec has no open
questions and no unconfirmed decisions left — at which point a re-run has nothing to clarify and would
only re-derive settled answers. `/kaba:fix-tests` is ungated for the same family of reason: it is the
NO-GO remediation loop, re-run by design. `/kaba:architecture` and `/kaba:architecture-diff` target
`.kaba/architecture.md`, which is tracked in git and therefore recoverable — the precise property the
feature directory lacks.

Answering yes simply proceeds and regenerates. Nothing is archived: a `.bak` file would leave stale
artifacts in a directory the pipeline reads, and the ask says the previous version is unrecoverable
because it is.

### Session Lock

The two-session boundary is enforced by a lock with one state file and one rule engine, consumed by two hooks:

- **State**: `.kaba/session-lock` (git-ignored) holds `test` or `implement`; absent = unrestricted. `/kaba:implement-tests` sets `test` at its start; `/kaba:implement-code` sets `implement` at its start and clears the lock after all end gates pass — a completed feature leaves the repo unrestricted, so the lock is armed only between the test session and the end of the implementation session. Manual override: `$(git config kaba.scriptdir)/session-lock.sh status|clear`.
- **Rules** (complement of `test_dir`, derived from `.kaba/config.yml`, in `session-lock.sh check`): `implement` may write everything **except** `test_dir`; `test` may write **only** `test_dir`, `feature_dir`, and the configured `test_writable` carve-outs. The rule is a complement, not a hand-maintained deny-list of implementation territory — nothing project-specific needs to be kept in sync as the codebase grows.
- **PreToolUse guard** (`hooks/hooks.json`, self-registered by the plugin — no `settings.json` edit needed): blocks the agent's `Write`/`Edit`/`NotebookEdit` calls to locked paths at the moment of the edit, giving real-time feedback on path-declaring tool calls.
- **SessionStart rewire** (same file): re-points `kaba.scriptdir` at the plugin copy that is actually running. `/kaba:init` pins that path absolutely, and a marketplace install puts the version in it, so every version bump would otherwise strand it — leaving new command text calling scripts out of the old directory. Fails open in any repo without `.kaba/config.yml`, and never pins at a scripts directory that does not exist.
- **Pre-commit hook** (`.kaba/hooks/pre-commit`, installed into the consumer repo by `/kaba:init`): validates staged paths at the commit boundary via `core.hooksPath`. (`--no-verify` can bypass — guardrail, not security.)

The **guarantee** is the pair of git-based checks — the pre-commit hook and the implementation session's end gates. They inspect the working tree and the index, so they are indifferent to how a change arrived. The PreToolUse guard is real-time feedback layered on top of them, not a substitute.
