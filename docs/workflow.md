# TDD-First Workflow for AI Coding Agents

This is kaba's workflow documentation — the pipeline the plugin's commands implement, and the
reasoning behind it. For installation and command-by-command usage, see the repo
[README](../README.md).

### Core Insight

Standard AI coding agents don't do TDD. When told "use TDD," they write code first, then tests. Prompts are suggestions — agents drift from them.

**Enforce workflow constraints with validation hooks (commands that return pass/fail), not prompts.** If you can express a rule as a command, don't express it as a prompt.

### Key Advantages

1. **Tests are easier to review than code** — especially with shoulda syntax (reads like English). If the tests are correct, the implementation is reviewable by the test suite itself.
2. **Mechanical checks catch drift** — git hooks and inline end gates reject boundary violations during the normal verified workflow. They are guardrails for a cooperating agent, not security against a hostile one.
3. **Test snapshots catch regressions** — by recording which tests are red/green before and after each session, you detect unintended side effects automatically.
4. **Separation of concerns** — separate test-author and implementation sessions reduce bias toward a particular implementation. Independent source/evidence review checks the remaining assumptions and coverage gaps.
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
| 5 | `/kaba:acceptance-criteria` | Derive grouped behavioral criteria with explicit variants/evidence and separate Delivery Obligations | `FEATURE_DIR/acceptance-criteria.md` |
| 6 | `/kaba:plan-tests` | Plan test organization — files, factories, helpers, outcome/variant evidence mapping, state-change allowlist. Also serves as the task list for implement-tests (no separate tasks step needed). | `FEATURE_DIR/test-plan.md` + `test-plan.json` |
| 7 | Snapshot: capture baseline | Run test suite, save state to file | `FEATURE_DIR/snapshots/baseline.json` |
| 8 | `/kaba:implement-tests` | Agent writes all test code following the test plan. Only permitted test-session paths. | Tests and support files under configured ownership patterns |
| 9 | Snapshot: capture post-test | Run test suite, save state to file | `FEATURE_DIR/snapshots/post-test.json` |
| 10 | Snapshot: compare | Compare post-test vs baseline (see Snapshot Comparison Rules) | Pass/fail report |
| 11 | Script: banned patterns | Runner-specific source quality — Go supported registrations/removal markers, or RSpec message-expectation/any-instance/`respond_to` bans | Pass/fail |
| 12 | `/kaba:review-tests` | Agent review — "could a terrible implementation pass these tests?" | Structured findings report |
| 13 | `/kaba:fix-tests` | *(optional — only on a NO-GO verdict)* Apply the review findings to the test files — mechanical fixes directly, escalated findings resolved with the human — then re-validate (snapshot + banned-pattern scan) and request independent scoped review | Updated test files + `FEATURE_DIR/test-fixes.md` |
| 14 | Human review | Review test descriptions, coverage/evidence, planned delivery checks, and independent findings after corrections. Final go/no-go. | Go/no-go |

#### Phase 3: Implementation Session

| Step | Command / Action | Purpose | Output |
|------|-----------------|---------|--------|
| 15 | `/kaba:plan-code` | Plan implementation informed by the locked tests — components, schema, decisions, build order | `FEATURE_DIR/code-plan.md` |
| 16 | `/kaba:implement-code` | Agent implements approved behavior, greens locked tests, completes Delivery Obligations and non-automated runtime checks. Cannot touch test-owned files. | Implementation files |
| 17 | Snapshot: capture post-impl | Run test suite, save state to file | `FEATURE_DIR/snapshots/post-impl.json` |
| 18 | Snapshot: compare | Compare post-impl vs post-test (see Snapshot Comparison Rules) | Pass/fail report |
| 19 | Gate: linter | The project's configured linter (`linter_command`) must pass; any suite-embedded checks (e.g. N+1 detection) ride along for free inside the same green `test_command` run | Pass/fail |

Behavioral coverage maps each criterion's related outcomes and named required variants to one
or more evidence locations; coherent tests can cover several criteria. Manual, command, and
source/configuration runtime checks remain explicit. Delivery Obligations preserve documentation,
configuration examples, CI/setup verification, and completion tasks separately. Runtime configuration
behavior, security guarantees, deadlines, and user-visible setup behavior remain behavioral
requirements. Snapshot gates protect suite state and identities; source/evidence completeness is
reviewed by the agent and human. Corrected tests return to an independent scoped reviewer, whose
report preserves unaffected findings, before human acceptance and the fresh implementation session.

Steps 17–19 run **inline inside `/kaba:implement-code`** as end gates (same pattern as implement-tests owning its snapshot steps), plus a fourth inline gate: `session-lock.sh check-dirty implement` must pass for all changed paths. Go snapshots also compare the complete protected file inventory, including ignored fixtures and helpers.

#### Phase 4: Completion

| Step | Command / Action | Purpose | Output |
|------|-----------------|---------|--------|
| 20 | `/kaba:architecture-diff` | Fold this feature's architectural delta into the doc | Updates `.kaba/architecture.md` |
| 21 | Script: `$(git config kaba.scriptdir)/cleanup-tests.sh` | *(when the feature has removals or scaffolds)* Delete exact tests marked REMOVED and recorded completed-feature scaffold sources; self-verifying with rollback; human reviews the deletion diff | Updated test files |

#### Outside the pipeline: `/kaba:research`

`/kaba:research` is deliberately **not** a step in this workflow. It is an optional, human-triggered decision-support command: when the human needs more information to make a decision — at any phase — it investigates one open question for the current feature and appends a recommendation to `FEATURE_DIR/research-log.md`. Its output informs the human only; no workflow command reads it.

### Runner contracts

Read [runner and ownership contracts](test-runners.md) for source forms, identity syntax,
criterion comments, scaffold restrictions, and cleanup. Go uses
`IMPORT_PATH::TestName/subtest`; RSpec uses positional example addresses. Go capture
requires all source-discovered cases and parents to produce complete runtime outcomes;
compilation errors and hidden cases invalidate capture. Package/build context must stay
consistent across snapshots. Only post-test enables validated overlays; post-implementation
uses real code. Any overlay-assisted capture rejects PINs. Test-owned Go helpers, fixtures,
and scaffolds remain protected through implementation even when Git ignores them.

The structural Go quality scan runs in the red test phase without executing the aggregate
quality command. The configured `linter_command` must succeed at implementation completion
and cleanup eligibility. It may include project-specific assertions, integration checks,
formatting, static analysis, vulnerability checks, and race detection. A failure blocks
completion; the session lock stays armed.

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

Successful Go post-test comparison also records the implementation's required passing
identities: new tests and tests covered by MODIFY entries. Post-implementation comparison
uses this validated set to reject incomplete feature implementations while preserving
the status of unrelated baseline failures.

#### Post-Implementation (snapshot 3 vs post-test)

| Test Category | Expected State | Violation Means |
|---------------|---------------|-----------------|
| New tests (from this feature) | Green (passed) | Implementation incomplete |
| Modified tests (from this feature) | Green (passed) | Implementation incomplete |
| All other previously green tests | Green (passed) | Unintended regression |
| All other previously red tests | Red (failed) | Accidental fix or interference |
| Existing test content | Unchanged structural digest when available | Test edited during implementation |

### Snapshot Script Invocation Map

The snapshot script (`$(git config kaba.scriptdir)/snapshot-tests.sh`) is called inline by commands, same as `resolve-feature.sh`. No host lifecycle hooks are needed.

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
| `cleanup-tests.sh` (own script) | Human-triggered, between features | Deletes marked tests and recorded Go scaffolds; verifies identities and real suite with exact rollback |

### Mechanical Enforcement vs. Prompt-Held Rules

| Concern | Enforcement | Mechanism |
|---------|-------------|-----------|
| No implementation code in test session | Real-time hook + git boundary | Session lock (`test` mode): PreToolUse guard blocks agent edits to implementation paths in real time; pre-commit rejects staged implementation paths |
| No test changes in implementation session | Real-time hook + git boundary + inline end gate | Session lock (`implement` mode): PreToolUse guard blocks test-owned edits; pre-commit rejects forbidden staged paths; classifier-based ownership end gate in `implement-code` |
| Runner-specific test source quality | Inline script gate | `$(git config kaba.scriptdir)/banned-patterns.sh`, pass/fail |
| Snapshot comparison rules | Inline script gate | `snapshot-tests.sh`, invoked by the owning skill, pass/fail |
| Project quality command | Inline command gate | The project's configured `linter_command` at implementation completion (`.kaba/config.yml`), nonzero exit blocks completion |
| N+1 query detection (if the suite has it, e.g. Prosopite) | Test-suite gate | Rides along inside the `test_command` green run, pass/fail |
| Test plan criterion coverage | Prompt | Agent follows test plan structure |
| Code architecture decisions | Prompt | Agent follows implementation plan |
| Re-run overwrite confirmation | Prompt | `check-artifacts.sh` answers *has this step already completed?*; the command's own step 1 acts on the answer (see **Re-running a step**) |

The overwrite confirmation is the one rule in this table that is prompt-held by necessity rather than
by choice. Nothing can force the agent to *run* the script, and `PreToolUse` does not fire until write
time. That is too late for this concern: the cost being prevented is a whole regeneration's worth of
analysis, spent before a single byte is written. The later git and inline gates protect repository
state, but cannot recover that wasted work.

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
- **Rules** (`.kaba/config.yml`, through `path-permissions.sh`): explicit configurations
  use independent allow/exclude lists for `test` and `implement`; exclusions win per
  session. Shared paths are writable in both; neither-owned paths are denied in both.
  Legacy RSpec configurations permit `test_dir`, `feature_dir`, and literal
  `test_writable` in test mode and everything except `test_dir` in implementation mode.
  Classifier checks cover future/deleted files, symlink lexical/resolved permissions,
  staged/unstaged/untracked changes, and both rename endpoints.
- **PreToolUse guard** (`hooks/hooks.json`, self-registered by the plugin): blocks Claude's direct-path edit tools and every declared path in a Codex `apply_patch` call, giving real-time feedback before path-declaring edits.
- **SessionStart rewire** (same file): re-points `kaba.scriptdir` at the plugin copy that is actually running. `/kaba:init` or `$kaba:init` pins that path absolutely, and a marketplace install puts the version in it, so every version bump would otherwise strand it — leaving new skill text calling scripts out of the old directory. It resolves Claude's project environment or Codex's `cwd` payload, fails open in any repo without `.kaba/config.yml`, and never pins at a scripts directory that does not exist.
- **Pre-commit hook** (`.kaba/hooks/pre-commit`, installed into the consumer repo by `/kaba:init`): validates staged paths at the commit boundary via `core.hooksPath`. (`--no-verify` can bypass — guardrail, not security.)

The **normal-workflow guarantee** is the pair of git-based checks — the pre-commit hook and the implementation session's end gates. They inspect the working tree and the index, so they are indifferent to how a change arrived. The PreToolUse guard is real-time feedback layered on top of them, not a substitute. These are drift controls for a cooperating agent, not a security boundary against deliberate bypass.
