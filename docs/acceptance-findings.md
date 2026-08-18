# Acceptance Findings — the end-to-end run

Defects and manual workarounds observed while running the `/kaba:` pipeline on markly
(feature `006-bookmark-favorites-a-boolean`). Anything listed here is a kaba defect, not a
Markly quirk. This list is the v1.1 backlog.

## F-1: Commands overwrite prior output without confirmation

**What happened:** `/kaba:plan-tests` was accidentally invoked a second time after it had
already completed. The command regenerated `test-plan.md` and `test-plan.json` from scratch
and silently overwrote the existing files. The first plan was unrecoverable — feature
artifacts under `features/<feature>/` are untracked until later in the pipeline, so there
was no git copy to restore.

**Impact this run:** a full plan-tests run's time and tokens spent regenerating an
artifact that already existed, plus the verification pass to confirm the replacement was
usable. The regenerated plan turned out materially equivalent (same 7 new examples into
the same 4 files, no modify/remove dispositions, same empty `test-plan.json` entries), so
no work had to be redone — but it also drifted in detail (contract deltas 2 → 1, sweep
hits 32 → 31), showing a re-run is a fresh derivation, not a reproduction. Had the first
plan already been consumed downstream (tests implemented against it), the silent
overwrite would additionally have desynced plan and suite.

**What was done:** compared the regenerated plan against the controller's notes on the
first version, confirmed material equivalence, proceeded.

**Required change (user-requested during the acceptance run):** every pipeline command
whose output files already exist on disk (proof of a prior completed run) must stop and
ask for explicit confirmation before doing anything else — before any analysis or
generation work spends tokens, not merely before writing the files — e.g. "test-plan.md
already exists for this feature; overwrite? (the previous version is not recoverable)".
Applies to all artifact-producing commands: specify, acceptance-criteria, plan-tests,
plan-code, implement-tests, implement-code — not just plan-tests.

Exception — clarify (user-ruled): re-running clarify is a legitimate way to resolve
something still unclear, so it must NOT gate on its output existing. Clarify asks for
confirmation only when the spec has no open questions left — then a re-run has nothing to
clarify and would only re-derive settled answers.

## F-2: No allowlist vocabulary for expected-green new tests (pins)

**What happened:** implement-tests wrote the 7 planned examples exactly as specified, but
the post-test snapshot compare returned **FAIL (4 violations)** — "new test should be
failed, got passed" — for precisely the 4 examples the test plan explicitly declared
would land green (MODEL-002, CRT-001, CRT-002, FLT-002: pins of already-conforming but
untested behavior). The 3 PRM examples landed red as planned; 391 existing examples
unchanged; banned-patterns PASS.

**Root cause:** a vocabulary gap between planning and enforcement. plan-tests knows the
pin concept (its output states which new examples "land green — the behavior already
conforms but is untested"), but the schema-v2 allowlist in test-plan.json only has MODIFY
and REMOVE actions, and snapshot-tests.sh compare hard-codes `NEW → failed` with no
allowlist consultation for new examples. A plan the pipeline itself produced is
inexpressible to the gate that judges it.

**What was done:** controller verified each of the 4 "violations" is exactly a planned
pin (tags match the plan's criteria mapping), treated the FAIL as a human-accepted
override at the go/no-go, and proceeded. The post-impl compare is unaffected: it baselines
against post-test.json, where the pins are already passing.

**Required change:** add an allowlist action for expected-green new examples (e.g.
`NEW-GREEN` / `PIN` entries carrying the planned identity), emitted by plan-tests for
pins and consumed by compare so `NEW → failed` applies only to unlisted new examples.
Until then, every feature that pins existing behavior — common on brownfield consumers —
ends its test session on a false FAIL that the human must override by eye.

## F-3: Compare is blind to content edits of existing examples

**What happened:** the snapshot compare keys examples by positional RSpec id and tracks
only status. An edit to a pre-existing example's body — or even its description — is
mechanically invisible so long as its status doesn't flip. Observed benignly: the
human-approved R1 fix rewrote PAGE-011's setup and assertion (passed → passed), and the
compare reported it as "unchanged". The same blindness would hide a test session
*weakening* an existing green example. Today the only guards on existing-test content are
model judgment (invalidation sweep, review-tests) and the human go/no-go — nothing
mechanical.

**Required change (design agreed with user during the run):**
1. Snapshot capture adds a per-example source digest: a Prism pass (tooling kaba already
   ships in scripts/ruby/) hashes each example block's AST, keyed by file + description
   path. AST hashing ignores formatting-only edits; loop-generated examples share their
   block's digest (a change flags the group — acceptable).
2. Compare adds the rule: digest drift on an example present in both snapshots with no
   status flip → violation unless allowlisted.
3. Allowlist vocabulary generalized once, jointly with F-2: entries become
   {action, expected_landing} — MODIFY → failed, REMOVE → pending, PIN → passed (F-2's
   expected-green new tests), TOUCH → status-preserving content edit (this finding).
4. Escalation writes the allowlist: when fix-tests escalates a fix outside plan scope and
   the human approves it, that approval authorizes appending the matching machine-readable
   allowlist entry. Without this, every approved escalation leaves test-plan.json stale
   (observed with R1/PAGE-011) and would false-fail the digest rule the moment it exists.

**Interim option if the Prism pass is deferred:** file-level rule in pure git — plan-tests
already knows which EXISTS files receive no changes; any working-tree diff in such a file
is a violation unless allowlisted. Partial coverage only (misses edits inside files that
legitimately gain new examples); a stopgap, not the fix.

## Run outcome

The pipeline completed end-to-end on feature 006-bookmark-favorites (2026-08-14/15):
specify → clarify → acceptance-criteria → plan-tests → implement-tests → review-tests →
fix-tests (incl. one interactive escalation) → plan-code → implement-code →
architecture-diff. Final state: 398 examples, 0 failures; single production edit
(one validation in Bookmarks::ListParams); rubocop clean; every Step 2 gate observed
firing, with one human override (F-2's four pin violations). Spec-kit remnant grep clean
outside frozen history. Three findings total: F-1 (overwrite confirmation), F-2 (pin
vocabulary), F-3 (content-edit blindness) — F-2 and F-3 share one root cause and one fix
(allowlist schema v3).
