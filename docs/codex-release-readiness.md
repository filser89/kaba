# Codex Release Readiness

**Last updated:** 2026-08-27
**Release rule:** Do not release Codex support while any BLOCKER or HIGH defect is open, or while
any required validation is incomplete.

This is the operational ledger for failures, fixes, and evidence discovered while validating Kaba
in Codex. The roadmap states the remaining direction; this file records what actually happened and
what must be true before release.

## How to use this ledger

- Add a finding as soon as a stress run exposes it. Preserve the original observation verbatim
  enough that another person can reproduce it.
- Keep confirmed defects separate from required validations that have not failed.
- A code change moves a defect to **FIXED — NEEDS VERIFICATION**, not directly to CLOSED.
- Close a defect only after its acceptance criteria pass in the real Codex consumer and the Kaba
  regression suite covers the mechanism where practical.
- Record accepted risks explicitly; silence never means acceptance.
- Keep stress protocols outside consumer repositories so their hidden prompts and answer keys do
  not influence the agent being evaluated.

Status values:

- **OPEN** — reproduced and not fixed.
- **FIXED — NEEDS VERIFICATION** — implementation changed; real-consumer verification remains.
- **CLOSED** — fix and verification evidence recorded.
- **ACCEPTED RISK** — Sergey explicitly accepted the release risk and rationale is recorded.
- **NOT STARTED / IN PROGRESS / PASSED / FAILED** — validation-run states.

## Current summary

### Confirmed and source-level defects

| ID | Severity | Status | Finding |
|---|---|---|---|
| CODEX-001 | BLOCKER | OPEN | A sandbox-denied Git-config write leaves partial initialization that rejects the escalated retry. |
| CODEX-002 | HIGH | OPEN | Skill handoffs and reports are authored with Claude `/kaba:*` syntax even when running in Codex. |
| CODEX-003 | HIGH | OPEN | Unlisted lifecycle ambiguities pass both clarification and acceptance gap gates as resolved. |
| CODEX-004 | HIGH | OPEN | Test planning passes mechanical validation after inventing unsupported and rule-conflicting test boundaries. |
| CODEX-005 | HIGH | OPEN | Test planning omits PIN entries for new negative examples whose behavior already conforms. |
| CODEX-006 | HIGH | OPEN | Greenfield test infrastructure is selected without human authorization. |
| CODEX-007 | HIGH | OPEN | Skills bypass configured rules authority with hard-coded `CLAUDE.md` reads. |
| CODEX-008 | HIGH | OPEN | Acceptance generation turns feature-local out-of-scope items into permanent negative behavior contracts. |
| CODEX-009 | HIGH | OPEN | An amendment request is treated as overwrite approval, bypassing the mandatory prior-run confirmation turn. |
| CODEX-010 | BLOCKER | OPEN | Mid-test criteria removal produces post-test REMOVE identities that cannot validate against the preserved baseline. |
| CODEX-011 | MEDIUM | OPEN | Scoped review clears findings but retains stale Strength Summary claims that the fixed weaknesses remain. |
| CODEX-012 | HIGH | OPEN | Scoped adversarial re-review clears a repair that only swaps one trivial passing stub for its symmetric alternative. |
| CODEX-013 | BLOCKER | OPEN | Full test review accepts service-only coverage for the feature's primary user journey, allowing an unusable implementation to pass. |
| CODEX-014 | HIGH | OPEN | Code planning moves service-owned workflow rules into the model to defend an explicitly unsupported write path. |

### Required release validations

| ID | Status | Validation |
|---|---|---|
| CODEX-V001 | IN PROGRESS | Complete Trialbook Feature 001 through all 13 Kaba skills in Codex. |
| CODEX-V002 | NOT STARTED | Repeat the same feature in Claude Code and compare workflow behavior. |
| CODEX-V003 | IN PROGRESS | Verify released Codex UI hook-trust onboarding without a bypass. |
| CODEX-V004 | NOT STARTED | Verify hook trust behavior after a Kaba plugin update/cache change. |
| CODEX-V005 | NOT STARTED | Recheck Codex edit surfaces that do not declare paths through `apply_patch`. |
| CODEX-V006 | NOT STARTED | Run final packaging, install, full-suite, documentation, and version-alignment checks. |

---

## CODEX-001 — Initializer cannot safely resume after sandbox escalation

**Severity:** BLOCKER
**Status:** OPEN
**First observed:** Trialbook greenfield run, `$kaba:init`, 2026-08-23

### Observation

The first initializer invocation could write normal workspace files but could not update the
sandbox-protected `.git/config`:

```text
error: could not lock config file .git/config: Operation not permitted
```

Before reaching that failure, `init-project.sh` had already created:

- `.kaba/config.yml`
- `.kaba/hooks/pre-commit`
- an empty `features/` directory

Codex then retried the same important command with elevated permission. The retry was rejected by
the initializer's own clobber guard:

```text
ERROR: .../.kaba/config.yml already exists — edit it by hand, or pass --force to rewrite it
```

The partial state did not contain the Git configuration or ignore rules the initializer promises:

- `core.hooksPath` was unset.
- `kaba.scriptdir` was unset.
- `/.kaba/session-lock` was absent from `.gitignore`.
- `/spec/examples.txt` was absent from `.gitignore`.

The installed `0.3.0` initializer was byte-identical to `scripts/init-project.sh`, ruling out a
stale-cache mismatch.

### Impact

A normal Codex permission escalation turns first-time onboarding into a partially initialized
repository and requires a new `--force` authorization. A user who mistakes the generated config
for success can continue without the Git hook, script path, or ignore rules that Kaba relies on.

### Required fix

Make initialization safe across an interrupted first run without weakening protection for genuine
pre-existing configuration. Acceptable designs include transactional rollback or an idempotent
resume that proceeds only when existing partial artifacts exactly match the requested approved
configuration. A blind automatic `--force` retry is not acceptable because it can overwrite user
configuration or an existing hooks integration.

Also update the Codex execution guidance if the host can predict that `.git/config` requires
elevated permission, so the initializer can request the needed authority before its first mutation.
The script must remain correct even when that prediction is unavailable.

### Closure criteria

- [ ] A simulated permission failure at the first `git config` call leaves either no partial state
  or a safely resumable, equivalence-checked state.
- [ ] Re-running the same approved command after escalation completes without `--force`.
- [ ] A different existing `.kaba/config.yml` still fails closed and is never overwritten.
- [ ] A conflicting pre-existing `core.hooksPath` still fails closed and is never overwritten.
- [ ] Successful recovery installs the hook, both Git config values, feature directory, and every
  requested ignore entry.
- [ ] Automated tests cover fresh success, partial failure, identical resume, differing-config
  refusal, and conflicting-hooks refusal under Bash 3.2-compatible code.
- [ ] The complete `$kaba:init` flow passes in a fresh Trialbook Codex session without manual
  cleanup or `--force`.

### Resolution evidence

Not fixed.

---

## CODEX-002 — Host-incorrect command syntax in skill handoffs

**Severity:** HIGH
**Status:** OPEN
**First observed:** Source audit during Trialbook stress-test preparation, 2026-08-23  
**Live reproduction:** Trialbook Feature 001, `$kaba:clarify`, 2026-08-23

### Observation

Codex explicitly invokes Kaba skills as `$kaba:<name>`, while Claude Code uses `/kaba:<name>`.
The shared skill bodies still hard-code Claude syntax in next-step guidance, error messages,
examples, and prior-run prompts. For example, the `init` skill points at
`/kaba:specify <one-liner>` after completion.

The README explains the host mapping, but a user following a skill's immediate handoff should not
need to translate a command manually. The Trialbook stress protocol treats any live `/kaba:*`
handoff in Codex as a compatibility failure.

During the Trialbook run, Codex completed `$kaba:clarify` and printed:

```text
Because title uniqueness affects validation and database design, I recommend one more
/kaba:clarify pass before /kaba:acceptance-criteria.
```

The later `$kaba:plan-tests` completion repeated the defect by directing the Codex user to
`/kaba:implement-tests`. The isolated Trialbook test review repeated it again: its Next Actions
directed the Codex user to `/kaba:fix-tests` after a NO-GO verdict. The final clean full review
repeated the same host-incorrect handoff by directing the Codex user to `/kaba:plan-code`.

This is a direct execution of the shared `skills/clarify/SKILL.md` instructions. Its Completion
Report and Next Step sections explicitly require `/kaba:clarify` and
`/kaba:acceptance-criteria`. The Codex-specific `skills/clarify/agents/openai.yaml` supplies display
metadata and disables implicit invocation, but provides no host-aware command rendering or syntax
translation.

### Impact

The functional skill can succeed and then give the Codex user a command that belongs to another
host. This breaks the guided workflow precisely at session boundaries and obscures whether the
plugin is actually ready for Codex users.

### Required fix

Introduce host-correct user-facing command rendering without duplicating the workflow or weakening
the shared skill source. Internal historical references may remain host-neutral, but every command
the current user is expected to invoke must use the active host's syntax.

### Closure criteria

- [ ] Every skill's completion handoff uses `$kaba:<name>` in Codex and `/kaba:<name>` in Claude.
- [ ] Errors and prior-run confirmations that recommend a command use the active host's syntax.
- [ ] Codex metadata/default prompts do not teach Claude-only slash syntax.
- [ ] Automated source tests prevent unqualified user-action `/kaba:*` handoffs from shipping in
  Codex-visible skill content, or an equivalent rendering mechanism is tested.
- [ ] A complete Trialbook run records host-correct handoffs at every phase boundary.
- [ ] Claude parity validation confirms its slash-command handoffs remain correct.

### Resolution evidence

Not fixed.

---

## CODEX-003 — Unlisted lifecycle gaps escape both specification gates

**Severity:** HIGH  
**Status:** OPEN  
**First observed:** Trialbook Feature 001, `$kaba:clarify` through `$kaba:acceptance-criteria`,
2026-08-23

### Observation

The initial `$kaba:specify` artifact listed five Open Questions covering draft/start readiness,
deliberate starting, framing preservation, and list content. It did not list whether starting is a
one-way transition, what repeated or concurrent Start attempts do, whether the original start time
is preserved, the canonical lifecycle terms, or what opening a started experiment displays.

This omission does not explain the complete escape by itself. `$kaba:clarify` is explicitly
required to scan the entire specification—not only Open Questions—across lifecycle/state
transitions, conflict resolution, terminology, and failure handling. The live run proved that this
broader scan executed: it asked about deletion and title uniqueness even though neither appeared in
the original Open Questions. Nevertheless, despite receiving an argument prioritizing lifecycle,
readiness, editability, and failure behavior, its completion reports marked Edge Cases & Failure
Handling resolved and Terminology & Consistency clear, then reported no critical ambiguity.

`$kaba:acceptance-criteria` provided a second independent gate. Its instructions require checking
whether a trivially wrong implementation could pass and placing ambiguous testable behavior under
Gaps & Open Questions. The live run performed that audit, added two other boundary criteria, but
still wrote `Gaps & Open Questions: None` while omitting the same unresolved lifecycle behaviors.

The repository skill bodies and the installed Trialbook `0.3.0` copies are byte-identical, ruling
out stale installed instructions.

### Impact

An implementation can allow a started experiment to return to draft, reset its original start time
on a repeated Start, behave nondeterministically under concurrent Start attempts, or expose an
underspecified started-detail view while satisfying every generated acceptance criterion. Each
stage reports completion, so the workflow converts missing decisions into false confidence instead
of surfacing them for the user.

### Required fix

Strengthen the cross-stage ambiguity contract so gaps omitted by `specify` cannot silently become
settled merely because Open Questions reaches empty. Preserve `clarify` as a whole-spec scan and
make its final category statuses evidence-based. Preserve `acceptance-criteria` as an independent
defense that must flag material testable ambiguity rather than trusting clarification's completion
report.

### Closure criteria

- [ ] A specification fixture with an empty or incomplete Open Questions list still causes
  `clarify` to surface material unconfirmed lifecycle transitions and conflict behavior.
- [ ] Clarify prioritization honors an explicit lifecycle/failure focus ahead of lower-impact
  identity or convenience questions.
- [ ] Clarify cannot mark lifecycle, terminology, or failure categories Clear/Resolved while
  repeated transitions, concurrency outcomes, or canonical states remain materially ambiguous.
- [ ] Acceptance-criteria generation independently lists those unresolved behaviors under Gaps &
  Open Questions and does not invent answers or report `None`.
- [ ] A trivially wrong implementation that permits reversal or resets the first start event is
  demonstrably excluded after the gaps are answered and criteria are regenerated.
- [ ] Regression coverage exercises the Trialbook failure chain across `specify`, `clarify`, and
  `acceptance-criteria`, including a question that was never placed in Open Questions.
- [ ] The corrected workflow passes in both Codex and Claude Code.

### Resolution evidence

Not fixed.

---

## CODEX-004 — Test plan crosses its architecture and dependency boundary

**Severity:** HIGH  
**Status:** OPEN  
**First observed:** Trialbook Feature 001, `$kaba:plan-tests`, 2026-08-23

### Observation

The generated plan is mechanically well-formed: all 45 criteria map exactly once, every per-file
mapping matches the final table, the state-change twin is valid schema-v3 JSON with an intentionally
empty entries array, and the zero-example invalidation sweep reports no contract deltas.

However, the plan chose `spec/system/start_experiment_spec.rb` while its own note acknowledged that
the confirmation presentation mechanism was not established. Trialbook has no Capybara or browser
driver dependency, and its Rails configuration disables generated system tests. The live command
read the Gemfile and test configuration before choosing this boundary. A runnable system spec would
therefore require an unapproved test-library and interaction-mechanism decision. `plan-tests` says
that a new dependency or test shape requiring an unestablished production fact must trigger its
escalation block and produce no plan.

The same plan placed start-readiness and post-start immutability under model validations in
`spec/models/experiment_spec.rb`. Trialbook's project rules assign business workflows and every
create/update operation to service objects while keeping models limited to persistence mapping,
associations, validations, and intrinsic model behavior. Treating the transition workflow as
direct model behavior both bypasses that authority and pressures implementation toward the wrong
owner.

### Impact

`implement-tests` must either invent and install browser-test infrastructure, silently choose a
confirmation technology, or fail to realize the planned system spec. Direct model tests for the
transition can also force business workflow into the model even though the repository explicitly
requires service ownership. The plan's complete mechanical PASS report hides both problems.

### Required fix

Make the resolution-chain and stop-test checks part of plan validation, not prose-only guidance.
Before selecting a test layer, verify that required test infrastructure exists and that the layer
does not contradict project-rule ownership. When confirmation behavior cannot be shaped without a
browser mechanism or dependency decision, emit the prescribed escalation block before writing
either plan artifact. When project rules already establish service ownership, keep workflow
criteria at an observable boundary or the established service boundary rather than reclassifying
them as model validations.

### Closure criteria

- [ ] A Rails/RSpec fixture without Capybara or a browser driver cannot produce a system-spec plan
  unless the needed infrastructure and interaction mechanism are supplied through the resolution
  chain.
- [ ] The unresolved confirmation-mechanism fixture emits the exact escalation block and writes
  neither `test-plan.md` nor `test-plan.json`.
- [ ] Start-readiness and post-start immutability are not assigned to model validations when
  project rules make the transition/update a service-owned business workflow.
- [ ] Existing configured fixtures remain usable without inventing a factory library.
- [x] After the human resolves the blocking boundary, the regenerated plan maps every criterion
  exactly once and emits valid schema-v3 JSON.
- [ ] Automated tests cover both missing-infrastructure escalation and project-rule-aware placement.
- [ ] The corrected planning behavior passes in both Codex and Claude Code.

### Resolution evidence

Not fixed.

### Containment evidence

The first `$kaba:implement-tests` run detected the unresolved confirmation interface before writing
any test code and emitted `ESCALATION — test-plan defect`. It preserved a version-2 baseline with
zero examples at SHA-256
`ceaf423d75daaa027ac1e30be58aba3738229eccd44aac2d8401d0dfb4eea9a1`, wrote the validated
`test-plan.lock.json`, and left the session lock in `test` mode for the documented re-plan/resume
path. This proves the downstream defense works; it does not satisfy the requirement that
`plan-tests` apply its own stop test before producing invalid artifacts.

The amendment path then passed. After the human chose a rendered confirmation step and restated
service/request ownership, `$kaba:plan-tests` replaced the unsupported system spec with request
specs, moved start readiness and post-start immutability out of model validation tests, mapped all
45 criteria exactly once in the per-file lists, describe coverage, and final mapping table, and
regenerated the empty schema-v3 state-change twin. The original zero-example baseline remained
byte-identical and the test lock remained armed. This verifies recovery from the live defect, not a
fix to the initial planning behavior.

A later clean-session derivation provided additional recurrence evidence after Trialbook's test
infrastructure was explicitly resolved in `AGENTS.md`. The planner correctly selected Factory Bot,
Capybara feature specs with Rack::Test, service specs for create/update/start, all 45 exact
mappings, and both LIFE PINs. However, it again assigned START-006 through
START-008—rejection by the Start transition when required framing is missing—to conditional
`started-state validation` examples in `spec/models/experiment_spec.rb`, despite the same plan
placing successful and optional-context Start behavior at the service boundary. The resulting plan
is structurally complete but still pressures workflow ownership into the model.

The targeted amendment then moved START-006 through START-008 into
`spec/services/experiments/start_spec.rb`, requiring each rejected operation result and reloaded
unfinished state while preserving the separate intrinsic draft-title validation. It retained the
Factory Bot design, the two Capybara/Rack::Test feature journeys, both exact LIFE PINs, and all 45
criteria exactly once in the per-file lists, describe coverage, and mapping table. No tests or
snapshots exist and the session lock is off. This verifies the recovery path for the recurrence;
the original planning defect remains unfixed.

The final 43-criterion full review found another structural recurrence. START-005 says that
confirming Start changes the experiment state, but the plan maps it only to a direct service spec.
The Capybara feature spec shows and cancels confirmation but never clicks `Confirm Start` and
observes the persisted transition. A no-op confirmation endpoint can therefore satisfy every
planned example while the service works in isolation. The reviewer rated this CRITICAL and
recommended an end-to-end Rack::Test journey, which requires moving or restructuring START-005 in
the plan rather than a mechanical assertion edit.

`fix-tests` then applied the other six review repairs, kept all 43 examples red, passed snapshot,
banned-pattern, and RuboCop gates, and emitted the required START-005 structural escalation without
editing the locked plan. The live plan and plan lock remain byte-identical. This is correct
downstream containment; START-005 still requires re-planning and in-progress test reconciliation.

The explicit workaround then removed the in-progress service-only START-005 example and stale
post-test snapshot before re-planning. The amended plan maps START-005 to a Rack::Test feature
journey that clicks Start and Confirm Start and observes the persisted transition; the service spec
retains START-006 through START-009. All 43 criteria map exactly once, schema-v3 entries remain
empty, the zero-example baseline checksum is preserved, and the worktree currently has the expected
42 unique markers with only START-005 awaiting `implement-tests`. The resumed implementation then
added exactly one START-005 Rack::Test journey under the planned confirmation context. It visits the
experiment, clicks Start and Confirm Start, and asserts the reloaded `started` state. The refreshed
post-test snapshot contains 43 failed examples with no load errors, all 43 markers are exact and
unique, and snapshot comparison plus banned-pattern checks pass.

---

## CODEX-005 — Already-conforming negative tests are not planned as PINs

**Severity:** HIGH  
**Status:** OPEN  
**First observed:** Trialbook Feature 001, amended `$kaba:plan-tests` followed by
`$kaba:implement-tests`, 2026-08-24

### Observation

Acceptance criteria LIFE-001 and LIFE-002 require the feature to provide no deletion or archival.
The amended plan mapped them to two new negative routing examples. Trialbook's greenfield
application already has neither route, so both examples must land green before feature
implementation.

`plan-tests` explicitly ran its new-route negative-guard sweep and observed no existing experiment,
delete, or archive routes, but still declared Planned State Changes `None` and generated an empty
schema-v3 entries array. Its own PIN rule requires every planned new example that already conforms
to be recorded as `PIN` with expected landing `passed` and an exact planned full description.

The next `$kaba:implement-tests` run detected the contradiction before writing test code and
escalated for two PIN entries. The baseline still contains zero examples, the validated plan lock
remains byte-identical to the empty live JSON, and the session lock remains in `test` mode.

### Impact

Without the downstream escalation, correct negative tests would fail the post-test snapshot gate
solely because they pass for the intended reason. The workflow cannot distinguish a legitimate
already-conforming boundary from a trivially green new test unless planning declares the PIN.

### Required fix

During planning, classify the expected pre-implementation landing of every new example. When a
criterion asserts absence or another already-conforming behavior, verify the current boundary and
emit an exact PIN in both the Markdown state-change table and schema-v3 JSON. Do not infer PINs from
negative wording alone; current behavior must be evidenced.

### Closure criteria

- [ ] A greenfield Rails fixture with no delete/archive routes produces one PIN for LIFE-001 and
  one PIN for LIFE-002.
- [ ] Each PIN uses the RSpec `./spec/...` file form and a full description matching the planned
  example byte-for-byte.
- [ ] The Markdown state-change table and generated schema-v3 JSON contain the same two PINs.
- [ ] `validate-plan` accepts both PINs against the zero-example baseline.
- [ ] The implemented negative examples land passed and post-test comparison accepts them while
  all non-PIN feature examples still have to land failed.
- [ ] A fixture where the negative behavior does not already conform does not receive a PIN.
- [ ] Automated regression coverage locks the already-conforming negative-route case.
- [ ] The corrected behavior passes in both Codex and Claude Code.

### Resolution evidence

Not fixed. The downstream escalation prevented test writes and supplied the required amendment.

### Containment evidence

The human re-ran `$kaba:plan-tests` with the escalation block. The amended plan now contains two
schema-v3 `PIN` entries, both landing `passed`, for
`./spec/routing/experiments_routing_spec.rb`. Their descriptions match the planned nested RSpec
descriptions byte-for-byte:

- `experiment lifecycle routes deletion is excluded`
- `experiment lifecycle routes archival is excluded`

The Markdown state-change table contains the same descriptions and landings. All 45 acceptance
criteria remain mapped exactly once in the per-file criteria lists, describe coverage, and final
mapping table; the earlier rendered-confirmation and service/request-boundary amendment is also
preserved. The version-2 baseline remains at zero examples. The old empty plan lock is expected at
this point: `implement-tests` writes the new lock only after its opening `validate-plan` succeeds.
This verifies the documented recovery path, not a fix to the original planning miss.

---

## CODEX-006 — Greenfield test infrastructure is selected without human authorization

**Severity:** HIGH  
**Status:** OPEN  
**First observed:** Trialbook Feature 001, `$kaba:plan-tests` followed by
`$kaba:implement-tests`, 2026-08-24

### Observation

Trialbook established RSpec but left the rest of its test infrastructure unresolved. Its project
rules and architecture did not decide its acceptance-test style, browser/system-test stack,
test-data mechanism, or supporting test libraries. Before Feature 001, `spec/` contained only the
RSpec helpers, with no existing convention to inherit.

No Kaba command asked the human to resolve or explicitly delegate those once-per-project choices.
The first plan silently selected a system-spec boundary despite the absence of an established
browser stack. After that defect was amended, `plan-tests` selected a new
`spec/fixtures/experiments.yml` fixture set, and `implement-tests` began applying the choice by
writing that file and `spec/models/experiment_spec.rb` with `fixtures :experiments`.

This behavior follows the current skill contract rather than violating it. `plan-tests` explicitly
classifies factory/trait design as test-suite organization that it owns and directs test placement
to fall back to the framework default. Although it forbids making library or architectural
decisions, the workflow has no complete human-authorization gate for missing cross-cutting test
infrastructure, so a framework fallback can silently become a permanent project convention.

### Impact

The first feature can silently establish project-wide testing conventions and spread them through
many planned files before the human sees executable tests. Changing them later can mean replanning
and rewriting test layers, feature files, browser helpers, fixtures/factories, drivers, and
dependencies. It also makes Kaba's claim that library and architectural decisions remain
human-owned misleading when the test architecture is still blank.

### Required fix

Treat missing test infrastructure as a project-level architecture decision, not ordinary
per-feature test organization. The configured project rules (`AGENTS.md`, `CLAUDE.md`, or their
equivalent from `.kaba/config.yml`) are the authoritative durable source. Do not create a separate
`.kaba/test-architecture.md`, which would duplicate general project policy and introduce precedence
and drift problems.

The prose-driven `$kaba:init` skill should own greenfield discovery and resolution. Before its
mechanical installer writes anything, it must read the configured rules, dependency manifests,
test configuration, existing suite, and application shape. It should distinguish a mature,
consistent convention from greenfield absence and maintain an internal capability checklist whose
relevant entries are explicit, established, delegated, not applicable, or unresolved. Relevant
cross-cutting capabilities include:

- acceptance style/runner, such as RSpec request specs or Cucumber features;
- browser/system-test stack, such as Capybara plus an approved driver, another browser tool, or no
  browser layer;
- test-data mechanism, such as Rails fixtures, an approved factory library, or local builders;
- other supporting libraries or helpers that will become suite-wide conventions.

Cucumber and Capybara occupy different layers and may coexist; the gate must present concrete,
project-appropriate decisions rather than flattening every tool into one either/or question.

Every missing choice must be resolved in one of two ways: the human chooses it, or the human
explicitly delegates that defined decision to the AI. Silence, a framework default, and the mere
absence of an existing convention are not authorization. Questions must be framework-agnostic and
selected from the detected application shape rather than emitted as a universal framework-specific
questionnaire.

After resolution, `$kaba:init` must show the exact proposed project-rules edit and obtain explicit
approval before applying it to the human-selected configured rules file. The recorded rules must
contain the concrete convention and any delegation scope, so the decision is made once, visible to
all agents, and inherited by later features. The existing `init-project.sh` remains a deterministic
mechanical installer for `.kaba/config.yml`, hooks, Git configuration, and ignore entries; dynamic
stack reasoning and rules authoring stay in the prose skill. Its current blanket statement that all
writing belongs to the script must be narrowed accordingly: the script exclusively owns Kaba setup
files, while the skill may update an explicitly approved rules file.

As a downstream defense, `plan-tests` must stop before writing plan artifacts whenever shaping the
tests requires unresolved infrastructure. Once the infrastructure is established or explicitly
delegated, `plan-tests` may own ordinary per-feature organization within it—for example file
placement, fixture/factory variants, associations, describe blocks, and helper reuse.

### Closure criteria

- [ ] `init` reads configured rules, manifests, test configuration, existing tests, and application
  shape before proposing test-infrastructure decisions.
- [ ] It distinguishes mature, consistent evidence from greenfield absence and internally
  classifies relevant capabilities as explicit, established, delegated, not applicable, or
  unresolved.
- [ ] Its questions are framework-agnostic, capability-based, and limited to the detected
  application's relevant unresolved decisions.
- [ ] The human can either choose each missing convention or explicitly delegate the defined choice
  to the AI.
- [ ] Framework defaults and absent conventions are never treated as implicit human authorization.
- [ ] The prompt explains viable project-specific choices and relevant trade-offs without assuming
  or installing dependencies.
- [ ] Before persistence, `init` shows the exact rules-file edit and obtains explicit approval; it
  then writes the decision and delegation scope to the selected configured project-rules file.
- [ ] `init-project.sh` remains responsible only for deterministic Kaba setup while the skill owns
  the approved project-rules update.
- [ ] If initialization did not resolve a subsequently required capability, `plan-tests` stops
  before writing artifacts and asks the human to choose or explicitly delegate it.
- [ ] After infrastructure is established, subsequent features reuse it without asking again.
- [ ] A mature project with an observable existing convention inherits it without interruption.
- [ ] Per-feature organization remains plan-owned after its infrastructure is established.
- [ ] Automated regression coverage exercises human choice, explicit delegation, refusal to infer
  authorization, and mature-project inheritance.
- [ ] The corrected behavior passes in both Codex and Claude Code.

### Resolution evidence

Not fixed. The human approved the design above on 2026-08-24. No skill or script changes have been
made during the active Trialbook stress test.

### Containment evidence

The human interrupted `$kaba:implement-tests` after it wrote the fixture and the first model spec.
No production application files were changed. The partial fixture, model spec, version-2
zero-example baseline, and amended two-PIN plan lock were moved to the recoverable archive
`/private/tmp/trialbook-p2-codex006.vhyBQp`; the archived baseline retains SHA-256
`a7b717b4e7526e0b6c54554faa755494da547564cdee90dc6c6a3dcefee9841e`. The supported session-lock
command then cleared the `test` lock. Trialbook is back at a pre-planning boundary with only its
RSpec helpers in `spec/`, while the prior plan artifacts remain for the required overwrite gate.
The earlier unsupported browser/system-test selection remains separately recorded as the concrete
`plan-tests` failure in CODEX-004; CODEX-006 records the broader missing authorization contract that
allowed both categories of assumption.

For Trialbook specifically, the human selected thoughtbot's Rails testing conventions as the
baseline. Its `AGENTS.md` now records RSpec request/service/model ownership, Factory Bot instead of
Rails fixtures, `build_stubbed`/`build` preference, a small Capybara acceptance layer using Rack::Test
when JavaScript is unnecessary, no Cucumber, and explicit approval for future infrastructure
changes. The plan was regenerated from those rules and the P2 interruption/resume probe completed
successfully. This project-specific resolution does not replace the framework-agnostic Kaba fix.

---

## CODEX-007 — Skills bypass configured rules authority with hard-coded `CLAUDE.md`

**Severity:** HIGH  
**Status:** OPEN  
**First observed:** Trialbook Feature 001, `$kaba:implement-tests`, 2026-08-25

### Observation

Trialbook has no `CLAUDE.md`. Its `.kaba/config.yml` explicitly declares
`rules_files: [AGENTS.md]`, and `AGENTS.md` contains the applicable architecture and testing rules.
During the interrupted test run, `implement-tests` nevertheless searched for `CLAUDE.md` and
reported its absence before also recognizing the configured authority.

This behavior is directly instructed by the skill. Both the repository and installed Kaba 0.3.0
copies of `implement-tests` say to read `CLAUDE.md` for project conventions and then separately read
the files selected by `.kaba/config.yml`. They also refer back to `CLAUDE.md` for removal idioms,
lazy symbol resolution, and framework conventions. Direct hard-coded reads or authority references
also exist in `plan-tests`, `review-tests`, `fix-tests`, and `implement-code`; other skills use
Claude/Agents filenames in explanatory examples instead of consistently naming configured rules.

### Impact

`rules_files` is not the actual single source of authority. In an AGENTS-only project the lookup is
noisy but survivable. If an unconfigured `CLAUDE.md` exists—for example a stale, host-specific, or
conflicting file—the skills are instructed to read and potentially obey it despite the project
explicitly excluding it. That can change test layout, banned patterns, generator behavior, or
implementation conventions and defeats host-neutral configuration.

### Required fix

Resolve project-rule files only from `.kaba/config.yml` and read exactly those files. Replace direct
`CLAUDE.md` reads and later “per CLAUDE.md” references with the configured project-rules authority.
Framework-owned values already present in config—test directory, test command, linter, writable
files—must continue to come from config rather than any hard-coded rules filename. Examples of a
durable convention may refer generically to a configured rules file instead of prescribing
`CLAUDE.md`.

An unconfigured rules-looking file must not become authority merely because it exists. A configured
file that is missing or unreadable must produce an explicit error rather than silently falling back
to a host-default filename.

### Closure criteria

- [ ] An AGENTS-only fixture never probes or reports on `CLAUDE.md` and applies `AGENTS.md` rules.
- [ ] A CLAUDE-only fixture reads the configured `CLAUDE.md` without probing `AGENTS.md`.
- [ ] A fixture containing both files obeys only the subset listed in `rules_files`.
- [ ] An unconfigured conflicting file cannot influence planning, implementation, review, or fixes.
- [ ] A missing configured rules file fails explicitly without fallback.
- [ ] Direct operational `CLAUDE.md` references are removed from `plan-tests`, `implement-tests`,
  `review-tests`, `fix-tests`, `plan-code`, `implement-code`, and related handoffs/examples.
- [ ] Automated skill tests lock configured-only authority across both supported hosts.
- [ ] The corrected behavior passes in Trialbook on Codex and in the Claude Code parity run.

### Resolution evidence

Not fixed.

### Containment evidence

Trialbook's run still read and applied the configured `AGENTS.md`; no conflicting `CLAUDE.md`
exists, so this occurrence did not corrupt the generated tests. The fresh-session resume completed
with the test-only lock still active, a byte-identical schema-v3 plan lock, and the original
version-2 zero-example baseline preserved at SHA-256
`b6815a090443086766b9812a34cdd486d73d390e348e1e0a4ce07870a2352e2d`. Its post-test snapshot records
45 examples: the two declared PINs pass and all 43 non-PIN examples fail.

---

## CODEX-008 — Feature-local exclusions become permanent negative behavior contracts

**Severity:** HIGH  
**Status:** OPEN  
**First observed:** Trialbook Feature 001, `$kaba:acceptance-criteria` through `$kaba:fix-tests`,
2026-08-26

### Observation

Trialbook's specification answers “Should experiments be removable in this feature?” with “No
deletion or archival” and lists both operations under `Out of Scope`. It does not state that the
product must permanently prohibit either operation. `acceptance-criteria` nevertheless generated
LIFE-001 (“This feature provides no way to delete an experiment”) and LIFE-002 (“This feature
provides no way to archive an experiment”) as executable behavioral contracts.

That conversion propagated through planning as two passing routing PINs. Adversarial review then
correctly observed that route absence did not prove the broad assertions, and `fix-tests` eventually
stopped because strengthening LIFE-002 to cover controls and generic updates would turn its locked
PIN into an implementation-dependent red test. The downstream conflict originates earlier: an
omitted feature was treated as a behavior the implementation must actively prevent.

### Impact

Feature scope becomes permanent product policy. Tests for functionality that was merely deferred
create artificial PINs, consume review and repair work, and can block a later feature that
legitimately introduces deletion or archival. The workflow also produces misleading evidence:
“currently absent because nothing exists yet” is mistaken for “already implemented and protected.”

### Required fix

Acceptance generation must distinguish an omission from a prohibition. Items described only as
“out of scope,” “not in this feature,” or equivalent must constrain planning and implementation
scope without becoming acceptance criteria. Generate a negative behavior criterion only when the
source establishes an observable invariant, authorization rule, safety boundary, compatibility
contract, or explicit product prohibition. If the wording is ambiguous, ask the human whether the
operation is deferred or forbidden before generating a negative criterion.

### Closure criteria

- [ ] A feature-local `Out of Scope: deletion` entry produces no no-deletion acceptance criterion.
- [ ] An explicit invariant such as “records can never be deleted” produces an executable negative
  criterion.
- [ ] Ambiguous exclusion wording triggers clarification rather than silently choosing permanence.
- [ ] Planning and implementation do not create PINs for omitted functionality alone.
- [ ] A later feature may introduce previously deferred functionality without contradicting an
  earlier feature's tests.
- [ ] Automated coverage validates the distinction in both Codex and Claude Code.

### Resolution evidence

Not fixed.

### Containment evidence

`fix-tests` preserved the locked plan and stopped at LIFE-002. The correct Trialbook recovery is to
remove LIFE-001 and LIFE-002 at the acceptance-criteria stage, then regenerate downstream artifacts;
strengthening either criterion would preserve the original category error.

---

## CODEX-009 — Amendment intent bypasses the prior-run overwrite gate

**Severity:** HIGH  
**Status:** OPEN  
**First observed:** Trialbook Feature 001, amended `$kaba:acceptance-criteria`, 2026-08-26

### Observation

The user invoked `$kaba:acceptance-criteria` with arguments describing an amendment to the existing
criteria. The command rewrote `acceptance-criteria.md` immediately without asking whether the prior
artifact could be overwritten and without ending the turn for a separate answer.

Both the repository skill and installed Kaba 0.3.0 skill explicitly require the opposite. Before
reading the spec, `check-artifacts.sh acceptance-criteria` must run; when it reports
`PRIOR_RUN=yes`, the agent must ask the overwrite question, end its turn, and continue only after an
explicit response. A post-run probe reports `PRIOR_RUN=yes` and
`EXISTING=acceptance-criteria.md`, confirming that the gate applies. User arguments describing the
desired replacement were incorrectly treated as authorization to destroy the current artifact.

### Impact

The workflow conflates semantic intent (“make this amendment”) with destructive authority (“replace
the existing untracked artifact now”). The prior version is not recoverable, so bypassing the
separate gate defeats the exact safeguard intended for re-runs and makes amendment behavior
inconsistent across skills and sessions.

### Required fix

Make the prior-run gate mechanically precede argument interpretation and artifact reads. An
amendment or regeneration request may explain why the user wants a re-run, but it must never count
as the gate's explicit confirmation. Persist enough pending invocation state to ask, end the turn,
and resume with the original arguments only after the user answers yes.

### Closure criteria

- [ ] Invoking `acceptance-criteria` with amendment arguments against an existing artifact asks the
  overwrite question and performs no reads or writes beyond the gate probe in that turn.
- [ ] The command resumes with the original amendment arguments only after a separate explicit yes.
- [ ] Declining preserves the existing artifact byte-for-byte and ends the run.
- [ ] The same behavior is enforced for every skill with a prior-run overwrite gate.
- [ ] Automated tests distinguish amendment intent from overwrite authorization in Codex and
  Claude Code.

### Resolution evidence

Not fixed.

### Containment evidence

The resulting Trialbook artifact contains the requested correction—43 criteria with LIFE-001 and
LIFE-002 removed—and downstream plan/review artifacts were not touched. The desired content does
not excuse the skipped authorization gate. The subsequent `$kaba:plan-tests` amendment did present
its overwrite question and waited for approval, so the live bypass is currently isolated to the
acceptance-criteria rerun rather than reproduced across both skills.

---

## CODEX-010 — Criteria-removal re-plan cannot reconcile in-progress new tests

**Severity:** BLOCKER  
**Status:** OPEN  
**First observed:** Trialbook Feature 001, amended `$kaba:plan-tests` after test implementation,
2026-08-26

### Observation

After LIFE-001 and LIFE-002 were removed from acceptance criteria, `plan-tests` correctly retained
43 exact criterion mappings and removed both PINs. It then found the two now-out-of-scope lifecycle
examples in the in-progress test suite and emitted two `REMOVE → pending` entries using identities
from the preserved post-test snapshot:

- `./spec/requests/experiments/lifecycle_spec.rb[1:1:1]`
- `./spec/requests/experiments/lifecycle_spec.rb[1:2:1]`

The version-2 baseline intentionally contains zero examples. Both REMOVE identities therefore have
no baseline match. `implement-tests` validates every plan entry against that baseline before writing
and permits REMOVE only for a resolvable existing example, so the regenerated plan cannot enter the
documented resume path. The live `test-plan.json` checksum also differs from the old validated plan
lock, as expected after re-planning; no command has yet been able to validate and replace the lock.

### Impact

Kaba can add tests after a zero-example baseline, but it has no coherent lane for removing those
same in-progress new tests when an upstream acceptance correction narrows the contract. Treating
them as pre-existing REMOVE entries conflicts with the baseline identity model and blocks
`implement-tests`. Continuing requires an undocumented manual deletion or snapshot manipulation.

### Required fix

Amendment planning must classify obsolete tests by their relationship to the preserved baseline:

- baseline-owned examples use the existing REMOVE → pending lane;
- examples introduced after the baseline but removed by an upstream contract amendment use an
  explicit in-progress reconciliation lane that safely removes them without pretending they were
  baseline examples;
- post-test identities must never be emitted as baseline REMOVE entries.

The plan should be mechanically validated against the preserved baseline before the amendment is
reported complete, and the resume flow must document which command removes in-progress orphaned
tests and refreshes the plan lock and post-test snapshot.

### Closure criteria

- [ ] Removing criteria after `implement-tests` can remove their newly introduced examples without
  modifying the preserved baseline.
- [ ] The amended schema distinguishes baseline removals from in-progress feature-test cleanup.
- [ ] Every generated identity validates against the snapshot its action semantics reference.
- [ ] The regenerated plan is rejected during planning if it cannot pass `validate-plan`.
- [ ] Resume preserves all still-mapped test edits, removes only orphaned examples, writes a new
  plan lock, and captures a valid post-test snapshot.
- [ ] Automated coverage exercises a zero-example baseline followed by criteria contraction in
  both Codex and Claude Code.

### Resolution evidence

Not fixed.

### Containment evidence

No resume command has run against the invalid plan. Trialbook still has its original zero-example
baseline, the stale previously validated lock, the in-progress lifecycle spec, and the R1–R9
review fixes. The failure is contained before further test mutation.

The lab then applied an explicit manual containment workaround. It moved the two-example lifecycle
spec and stale 45-example post-test snapshot to a temporary recovery directory, regenerated a plan
with exactly 43 mappings and an empty schema-v3 entries array, and preserved the original baseline
checksum `b6815a090443086766b9812a34cdd486d73d390e348e1e0a4ce07870a2352e2d`. The test lock remains
active. The old plan lock is intentionally stale until the next `implement-tests` opening
validation replaces it. This permits the stress run to continue but does not fix the missing
reconciliation lane.

The resumed `implement-tests` run then completed the manual recovery: the baseline checksum stayed
byte-identical, the live empty schema-v3 plan and new plan lock match at
`3ceb47b058a6cd194cdb516336d92d33fcadf642b6bcdc7efd0249fa003f2bc9`, the orphan lifecycle spec is
absent, and the new post-test snapshot contains exactly 43 failed examples with no load errors.
All 43 acceptance IDs appear once as trailing test markers, the banned-pattern scan passes across
eight spec files, and the baseline-to-post-test compare reports PASS with no allowlist entries.
This validates the explicit workaround; automatic criteria-contraction recovery remains unfixed.

---

## CODEX-011 — Scoped review leaves contradictory stale strength prose

**Severity:** MEDIUM  
**Status:** OPEN  
**First observed:** Trialbook Feature 001, scoped review from `$kaba:fix-tests`, 2026-08-26

### Observation

`fix-tests` repaired seven findings and its scoped isolated re-review correctly removed every
finding row, recomputed the counts to zero, and changed the advisory verdict to GO. The report's
Strength Summary was deliberately retained under the current scoped-merge rule. It therefore still
says that the Start flow is weak “apart from the absence representations above” and that LIST-004
“remains gameable because ID and timestamp order coincide,” even though the corresponding tests now
cover empty strings and create records in the opposite order from their timestamps.

### Impact

The durable review artifact contradicts itself: its structured findings and verdict say the tests
cleared, while its explanatory prose tells the human that the same defects remain. This creates
avoidable uncertainty at the human GO gate and can cause duplicate repairs or rejection of a valid
suite.

### Required fix

Scoped merging must not retain assertions about criteria that were just re-reviewed. Either update
the affected Strength Summary statements from scoped evidence, represent strengths in a
criterion-addressable structure that can be merged safely, or replace stale prose with an explicit
scope note that makes no current claim about repaired criteria. A GO report must contain no prose
asserting that a cleared weakness remains.

### Closure criteria

- [ ] Clearing a scoped finding removes or updates every Strength Summary claim about that finding.
- [ ] Unreviewed criteria retain their prior findings and accurate summary context.
- [ ] A scoped GO report contains no stale “remains weak/gameable” statement for cleared criteria.
- [ ] Deterministic reruns produce stable merged findings, counts, verdict, and explanatory prose.
- [ ] Automated coverage exercises partial and complete scoped clearing in Codex and Claude Code.

### Resolution evidence

Not fixed.

### Containment evidence

The actual Trialbook fixes are present. The refreshed post-test snapshot contains 43 failed examples
with no load errors, snapshot comparison passes with an empty allowlist, all 43 criterion markers
are exact and unique, and the banned-pattern scan passes across eight spec files. Independent
inspection confirms the seven repaired tests defeat the reviewers' passing stubs; only the retained
Strength Summary prose is stale. A subsequent full review overwrote that contradictory report, so
Trialbook's current artifact no longer contains the stale summary; the scoped-merge behavior that
produced it remains unfixed.

---

## CODEX-012 — Scoped re-review overfits the prior passing stub

**Severity:** HIGH  
**Status:** OPEN  
**First observed:** Trialbook Feature 001, `$kaba:fix-tests` scoped review followed by full
`$kaba:review-tests`, 2026-08-26

### Observation

The first full review showed that LIST-004 correlated creation timestamps with insertion order: the
older record was inserted first and the newer record second, so descending primary-key ordering
could pass. `fix-tests` followed the recommendation by reversing insertion order. Its scoped
isolated re-review then cleared LIST-004 and contributed to a zero-finding GO report.

The next full review immediately demonstrated the symmetric wrong implementation. With the newer
record now inserted first, ascending primary-key ordering passes while still ignoring `created_at`.
It rated LIST-004 CRITICAL. Its recommendation—insert the older record first—would restore the
original arrangement and again permit descending-ID ordering. A two-record test can always align
the expected binary order with one primary-key direction; a robust repair needs at least three
records whose timestamp order is non-monotonic with ID order, or an equivalent construction that
defeats both directions.

### Impact

The repair loop can oscillate between two individually demonstrated bad implementations while each
scoped review reports PASS. Human GO based on the scoped result would have accepted a gameable test.
The passing-stub filter proves one weakness but does not require the reviewer to search for nearby
symmetric stubs after the test changes.

### Required fix

Scoped re-review must re-run the full adversarial reasoning for each repaired criterion, not merely
verify that the previous stub no longer passes. For ordered data, selection, boundaries, and other
symmetric domains, it should explicitly test the natural inverse/dual implementation or require a
fixture shape that distinguishes the contractual dimension from every obvious proxy. Repair
recommendations must defeat the demonstrated class of wrong implementations rather than one member.

### Closure criteria

- [ ] An ordering repair is tested against both ascending and descending proxy orderings.
- [ ] The LIST-004 fixture uses a non-monotonic timestamp/identity arrangement that defeats both.
- [ ] Scoped re-review independently derives new passing stubs after every repair.
- [ ] A repair cannot clear merely by swapping the prior stub for its symmetric alternative.
- [ ] Automated repair/re-review coverage prevents two-state oscillation in Codex and Claude Code.

### Resolution evidence

Not fixed.

### Containment evidence

The subsequent full review caught the false clear before human GO or implementation. Trialbook
remains under the test-session lock with a 43-example all-red snapshot and a new NO-GO report. No
production code has been written. The next `fix-tests` run replaced the two-record fixture with
three records whose desired timestamp order is 2–1–3 by ID, asserted all three positions, and passed
its scoped re-review and mechanical gates. After the separate START-005 plan defect was resolved,
a fresh full isolated review covered all 43 criteria and returned GO with zero findings. Its current
Strength Summary explicitly recognizes the non-monotonic timestamp/insertion arrangement.

---

## CODEX-013 — Full review misses the absent user-facing creation path

**Severity:** BLOCKER  
**Status:** OPEN  
**First observed:** Trialbook Feature 001, post-GO `$kaba:plan-code` verification, 2026-08-27

### Observation

The feature's primary behavior is that a user can capture and save a new experiment. DRAFT-001
states, “A user can save a new engineering experiment before work begins.” The locked suite maps
that criterion only to `spec/services/experiments/create_spec.rb`; it has no request or feature
example for a new/create route, form, submission, or resulting saved experiment.

The final full `$kaba:review-tests` reviewed 43/43 criteria, returned GO with zero findings, and
called draft creation strongly constrained. The resulting `code-plan.md` demonstrates the surviving
wrong implementation: it plans `Experiments::Create`, but no controller new/create actions, creation
form, or new/create routes. All 43 examples can therefore pass while a user opening the application
has no way to create the first experiment.

### Impact

The full adversarial review can approve a suite that proves an internal operation but not the
user-visible capability named by the criterion. The implemented feature would be unusable without
fixtures, console access, or an unplanned interface. A 43/43 GO is not meaningful if it does not
check that the primary journey is reachable from a real application boundary.

### Required fix

Test planning and review must validate observation-layer alignment, not only whether each criterion
ID has an assertion. A criterion framed as a user action must be exercised through a user-visible
boundary unless the specification explicitly defines an API or internal operation as the product
surface. Full review must also perform cross-criterion reachability analysis: the suite should prove
that a user can enter, complete, and observe the feature's primary journey, rather than accepting
isolated lower-layer operations as a substitute.

### Closure criteria

- [ ] A test plan mapping “a user can create/save” only to a service example receives NO-GO.
- [ ] Trialbook DRAFT-001 includes a Rack::Test journey or equivalent approved application-boundary
  test that opens the creation surface, submits a title, and observes the persisted experiment.
- [ ] Review checks that every primary user journey has an entry point and observable completion.
- [ ] Lower-layer service coverage remains available without being treated as sufficient journey
  coverage.
- [ ] The amended suite fails an implementation containing `Experiments::Create` but no creation
  controller, route, or form.
- [ ] A fresh full isolated review catches the original weak suite and returns GO after repair.

### Resolution evidence

Not fixed. Containment succeeded because human verification of `code-plan.md` exposed the missing
entry point before production implementation began.

### Containment evidence

The amended test plan now assigns DRAFT-001 exclusively to a new Rack::Test creation journey that
opens the creation page, submits a title, and observes the saved unfinished experiment. It retains
the lower-level create-service examples while using a TOUCH entry only to remove the old DRAFT-001
attribution. The identity exactly matches the current committed 43-test suite. Because `spec/` is
clean, the next `implement-tests` run will recapture that suite as its baseline before validating
the TOUCH entry.

The resumed `implement-tests` run then recaptured the committed 43-example suite as its baseline,
validated and locked the amended plan, added the creation journey, and landed at 44/44 failed
examples with zero load errors. The new example visits `/experiments/new`, submits a title, requires
`Experiment.count` to increase, checks the rendered title and `unfinished` state, and independently
queries the persisted state. Baseline-to-post-test comparison passes with one expected unused-TOUCH
warning because removing the trailing criterion comment does not change the example digest; the
banned-pattern scan passes across all nine spec files.

The implementation now provides the matching `/experiments/new` form, create route/action,
`Experiments::Create` delegation, redirect, and saved unfinished display. The repaired DRAFT-001
journey passes in the independent 44-example verification run.

---

## CODEX-014 — Code plan relocates workflow rules into the model

**Severity:** HIGH  
**Status:** OPEN  
**First observed:** Trialbook Feature 001, `$kaba:plan-code`, 2026-08-27

### Observation

Trialbook's applicable `AGENTS.md` says that every update and business workflow goes through a
service object, models remain thin, and business logic must not live in models. Title presence and
case-insensitive uniqueness are explicitly exercised as model validations, but Start readiness and
post-start framing immutability are exercised through `Experiments::Start` and
`Experiments::Update`.

The generated plan nevertheless assigns both workflow rules to `Experiment`:

- the model component owns “started-state readiness” and “started framing immutability”;
- D3 rejects service-only checks because direct Active Record writes could otherwise bypass them;
- the build order says the model greens Start readiness and update immutability groups before the
  corresponding services.

Protecting direct model writes is not a grounded constraint here: project rules explicitly forbid
using direct Active Record writes for updates. The plan turned an unsupported bypass path into a
reason to place business workflow logic in the model, then reported that project rules were
respected.

### Impact

`implement-code` would be contractually directed to violate the architecture Sergey deliberately
established for this greenfield project. The first feature would set the wrong precedent for state
transitions and write workflows, while the service objects become thin wrappers around model-owned
business rules.

### Required fix

`plan-code` must distinguish intrinsic persistence validation from application workflow policy
using the actual project rules and locked test boundaries. Here, title presence/uniqueness and the
database state-value constraint may remain persistence concerns; readiness for Start and refusal of
post-start framing updates belong to `Experiments::Start` and `Experiments::Update`. It must not
invent support for rule-forbidden direct writes as a competing architectural requirement.

### Closure criteria

- [x] The amended Trialbook plan assigns Start readiness to `Experiments::Start`.
- [x] The amended plan assigns post-start framing immutability to `Experiments::Update`.
- [x] `Experiment` remains limited to persistence mapping, title validation, state-value validity,
  and other genuinely intrinsic concerns allowed by project rules.
- [ ] Plan validation rejects a component mapping that places explicitly service-owned workflow
  rules in the model.
- [ ] A regression fixture with the same service/model rules produces the corrected boundary in
  Codex and Claude Code.

### Resolution evidence

Not fixed. No Trialbook production code has been written.

### Containment evidence

The regenerated Trialbook plan covers all nine locked spec files and now states the corrected
boundary in its summary, component responsibilities, D1 decision, and build order. It adds the
creation route/controller/form/show path required by the repaired DRAFT-001 journey,
`Experiments::Start` exclusively owns readiness, `Experiments::Update` exclusively owns post-start
framing refusal, and `Experiment` is limited to title/state validity plus persistence mapping. No
production code has been written from the rejected plan.

The resulting implementation preserves that boundary: `Experiments::Start` performs readiness and
the transition, `Experiments::Update` refuses post-start framing writes, all controller writes
delegate to services, and `Experiment` contains only title uniqueness/presence and state-value
validations.

---

## Required validation runs

### CODEX-V001 — Trialbook Feature 001 complete Codex workflow

**Status:** IN PROGRESS

External lab protocol:
`../stress-tests/trialbook-feature-001-codex.md` (local-only, deliberately outside the consumer).

Required evidence:

- [ ] All 13 Kaba skills explicitly invoked in Codex.
- [ ] Host-correct handoffs at every phase boundary — **FAILED** at the `$kaba:clarify`
  completion; tracked as CODEX-002.
- [ ] Unlisted material ambiguities are caught before test planning — **FAILED** across
  `$kaba:specify`, `$kaba:clarify`, and `$kaba:acceptance-criteria`; tracked as CODEX-003.
- [ ] Test planning honors dependency escalation and project-rule ownership — **FAILED** at
  `$kaba:plan-tests`; tracked as CODEX-004.
- [x] `implement-tests` catches the unsupported confirmation boundary before writing tests and
  preserves its baseline for re-planning — containment PASS for CODEX-004.
- [ ] Already-conforming new examples are declared as PINs during planning — **FAILED** for
  LIFE-001 and LIFE-002; tracked as CODEX-005.
- [x] The CODEX-005 re-plan adds the exact two PINs while preserving all 45 mappings and the prior
  confirmation/service-boundary amendment; opening `validate-plan` remains to be exercised.
- [ ] Greenfield test infrastructure is human-chosen or explicitly delegated before planning or
  implementation establishes project-wide conventions — **FAILED**; tracked as CODEX-006.
- [ ] Skills resolve project rules exclusively from `.kaba/config.yml` without hard-coded host
  filenames — **FAILED**; tracked as CODEX-007.
- [ ] Feature-local out-of-scope items remain planning boundaries instead of executable permanent
  prohibitions — **FAILED**; tracked as CODEX-008.
- [ ] Arguments reach `architecture`, `specify`, `clarify`, `research`, and `plan-code` as used by
  the protocol.
- [ ] Completed-step prior-run gates ask, end the turn, and preserve artifacts after decline —
  **FAILED** when amendment arguments bypassed the acceptance-criteria gate; tracked as CODEX-009.
- [ ] Upstream criteria contraction reconciles in-progress new tests against the preserved baseline
  and produces a valid resumable plan — **FAILED**; tracked as CODEX-010.
- [ ] Scoped review merges clear findings without retaining contradictory stale explanatory prose —
  **FAILED**; tracked as CODEX-011.
- [ ] Scoped re-review defeats the class of demonstrated wrong implementations instead of only the
  prior concrete stub — **FAILED**; tracked as CODEX-012.
- [x] Interrupted `implement-tests` preserves its baseline and resumes idempotently — P2 PASS: the
  baseline checksum remained unchanged, all 45 planned criteria were implemented exactly once, the
  two declared PINs passed, and all 43 non-PIN examples failed.
- [x] The test-session lock rejects a mixed multi-path `apply_patch` atomically — P3 PASS: the
  forbidden `app/models/kaba_lock_probe.rb` caused rejection and neither requested file was created.
- [x] Pre-commit rejects a shell-created forbidden path — P3 PASS: the hook rejected
  `app/models/kaba_boundary_probe.rb`, no commit was created, and the probe was removed cleanly.
- [x] Reviewer uses exactly one no-history child and does not leak the conversation marker — P4
  isolation PASS: the transcript shows one `/root/isolated_test_review` child, the parent only
  waited and relayed its summary, and `TRIALBOOK-CONTEXT-LEAK-7421` is absent from the report and
  repository artifacts.
- [x] Engineered weak test produces NO-GO; `fix-tests` repairs and scoped review clears it — P4
  detection PASS: START-005 received a CRITICAL finding, a concrete passing stub, and the expected
  persisted-transition repair. The generated plan has no HTTP start-transition example, so the
  probe used the architecture-equivalent service success assertion. After the 43-criterion recovery,
  a fresh full review confirmed that finding and the other original findings were cleared, then
  found one new HIGH ordering weakness and six MEDIUM blank-value boundaries. `fix-tests` repaired
  all seven, the mechanical gates passed, and the scoped isolated re-review cleared every finding.
- [x] Final full adversarial review covers all 43 current criteria and returns GO with zero findings;
  snapshot comparison and banned-pattern gates independently remain green.
- [ ] Primary user journeys are reachable through an approved application boundary — **FAILED**:
  the 43/43 GO suite permits a service-only create operation with no user-facing creation path;
  tracked as CODEX-013.
- [ ] Code planning preserves declared service/model ownership — **FAILED**: Start readiness and
  framing immutability were assigned to the model to defend direct writes forbidden by project
  rules; tracked as CODEX-014.
- [ ] Research remains advisory until the human passes its decision to planning.
- [x] Implementation passes snapshots, regression, untouched-test-directory, and linter gates —
  44/44 examples pass independently, post-test-to-post-impl comparison passes, `spec/` is clean,
  RuboCop reports zero offenses, Brakeman reports zero warnings, and the session lock is off.
- [ ] Completed `implement-code` prior-run gate asks before arming the lock or reading implementation
  context, preserves the implementation after decline, and leaves the lock off.
- [x] Greenfield `architecture-diff` fallback rebuilds the real architecture — the former skeleton
  was replaced by a full current-state scan anchored to implementation commit `dcfc438`, covering
  controllers, models, services, views, migrations, the service-owned mutation pattern, and actual
  architectural dependencies without feature/test inventory.
- [x] Final branch is clean, tests and RuboCop are green, and session lock is off — feature HEAD
  `bf06f54`; 44/44 RSpec examples pass, post-implementation snapshot comparison passes,
  RuboCop reports zero offenses, `git diff --check` passes, and no session lock remains. GitHub CI
  (`lint`, `scan_js`, `scan_ruby`) passed and private PR `filser89/trialbook#4` merged the feature
  into `master` as `bf7fc4a`; local `master` is clean and matches `origin/master`.

Record every failed checkbox as its own `CODEX-NNN` defect above before continuing release work.

### CODEX-V002 — Claude Code parity run

**Status:** NOT STARTED

Run the same Trialbook Feature 001 behavior and hidden answer key in Claude Code. Compare artifacts,
questions, state transitions, locks, snapshots, review isolation, gates, and architecture output.
Host-specific UI and invocation syntax may differ; behavioral contracts may not.

### CODEX-V003 — Released Codex hook-trust onboarding

**Status:** IN PROGRESS

Verify in the released Codex UI without a trust bypass:

- [ ] Installed SessionStart and PreToolUse commands are shown clearly before trust.
- [ ] The user can inspect exactly what will run.
- [ ] Declining trust leaves skills usable and git/end-gate guarantees intact.
- [ ] Accepting trust enables real-time lock feedback.
- [ ] Trust persists across fresh sessions as documented by the product.

### CODEX-V004 — Plugin update and trust/cache behavior

**Status:** NOT STARTED

- [ ] Install an updated/cachebuster Kaba build.
- [ ] Record whether Codex resets hook trust and how the UI communicates it.
- [ ] Open a fresh consumer session and verify SessionStart rewires `kaba.scriptdir` to the new
  cache path.
- [ ] Confirm no command or hook continues using the old plugin cache.

### CODEX-V005 — Non-`apply_patch` edit surfaces

**Status:** NOT STARTED

Inventory current Codex file-mutation tools and probe any that do not declare paths through
`apply_patch`. For uninspectable surfaces, confirm the pre-commit and implementation end gates catch
the resulting drift. Record whether additional real-time hook parsing is possible and warranted.

### CODEX-V006 — Final release checks

**Status:** NOT STARTED

- [ ] `bash test/run.sh` passes.
- [ ] `git diff --check` passes.
- [ ] Claude plugin validation passes.
- [ ] Codex plugin manifest and all `agents/openai.yaml` files validate.
- [ ] Fresh local marketplace install discovers exactly 13 namespaced Kaba skills and the intended
  hooks.
- [ ] Explicit invocation works; ordinary prompts do not implicitly invoke Kaba.
- [ ] Manifest, marketplace, changelog, tag, and release version agree.
- [ ] Installation and hook-trust documentation matches the released UI.
- [ ] Roadmap contains only future work; completed compatibility work is in the changelog.
- [ ] No BLOCKER/HIGH defects remain OPEN or FIXED — NEEDS VERIFICATION.
- [ ] Any ACCEPTED RISK has explicit Sergey approval and documented rationale.

---

## New finding template

```markdown
## CODEX-NNN — Concise failure title

**Severity:** BLOCKER | HIGH | MEDIUM | LOW
**Status:** OPEN
**First observed:** [consumer, feature/step, date]

### Observation

[Exact behavior, expected behavior, and reproducible error/output.]

### Impact

[What guarantee or user workflow this breaks.]

### Evidence

- [Repository-relative paths, commands, tests, artifacts, or safe external lab reference.]

### Required fix

[Outcome required; avoid prematurely prescribing an implementation when alternatives remain.]

### Closure criteria

- [ ] [Regression coverage]
- [ ] [Real-consumer verification]

### Resolution evidence

Not fixed.
```
