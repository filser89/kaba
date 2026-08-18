---
name: plan-tests
disable-model-invocation: true
description: Translate acceptance criteria into a concrete test plan — file locations, factory needs, shared contexts, and criterion-to-file mapping. No test code.
handoffs:
  - label: Implement Tests
    agent: kaba:implement-tests
    prompt: Implement tests following the test plan
    send: true
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). The user may provide additional constraints, focus areas, or corrections to scope.

## Purpose

This command takes the acceptance criteria (what to test) and produces a test plan (how to organize the tests). It makes structural decisions about the test suite — which files to create, what factories and shared helpers are needed, and which criteria land in which file — so that the test implementation step can focus purely on writing test code without making organizational choices. It also owns **invalidation discovery**: when the feature changes behavior the existing suite already exercises, this command is where every affected existing test is found and dispositioned — mechanically, suite-wide (see **Invalidation Sweep Rules**) — never left for implementation or review to notice.

This is a **planning step**, not a writing step. No test code is produced. The output is a map that the implement-tests step will follow.

**This command has exactly two goals:** (1) plan tests that satisfy the acceptance criteria (behavior), and (2) align the test suite with the **existing** architecture. It does **not** plan implementation, and it makes **no** architectural or library decisions. When an organizational choice would require deciding a not-yet-established fact about the production code, it stops and asks the human — see **Resolution Chain & Escalation** below.

## Outline

1. **Resolve feature paths, then check for a prior run**: Run `$(git config kaba.scriptdir)/resolve-feature.sh` from the repo root. It prints three `KEY=value` lines — `REPO_ROOT`, `FEATURE_DIR`, `FEATURE_SPEC` — read them line-by-line (never `eval`; a path may contain spaces).
   - **Prior-run gate — resolve this BEFORE reading any file.** A re-run regenerates the plan from scratch, so the gate must come before any analysis spends tokens, not merely before the write. Run `$(git config kaba.scriptdir)/check-artifacts.sh plan-tests` from the repo root and read its `KEY=value` lines:
     - `PRIOR_RUN=yes` — STOP and ask the user, naming what `EXISTING` lists (and mentioning `EMPTY` or `MISSING` if either is non-empty, since those mean the previous run crashed part-way): "`test-plan.md` and `test-plan.json` already exist for this feature — a prior run of `/kaba:plan-tests` completed. Overwrite? The previous version is not recoverable (feature artifacts are untracked at this stage), and a re-run is a fresh derivation, not a reproduction." Ask, then **end your turn** — do not answer yourself and do not proceed in the same response. Use `AskUserQuestion` if it is available. Continue only on an explicit yes.
     - `PRIOR_RUN=no` — proceed.
     - `PRIOR_RUN=unknown`, a non-zero exit, or no `PRIOR_RUN=` line at all — STOP and report the script's stderr verbatim. **Absence of an answer is never "no."**
   - Read the acceptance criteria from `FEATURE_DIR/acceptance-criteria.md`. If it does not exist, ERROR and stop.
   - Read the spec from `FEATURE_SPEC` (i.e. `FEATURE_DIR/spec.md`). If it does not exist, ERROR and stop.

2. **Load context and template**:
   - Read `.kaba/architecture.md` (if present) for the current structure of the codebase — its layers and where each kind of behavior is exercised. This is the authority for test placement (see step 3 and step 5). If the file is absent or still a bare skeleton (greenfield), note that and fall back to conventions/framework defaults.
   - Read the project rules (CLAUDE.md/AGENTS.md, per `.kaba/config.yml`'s `rules_files`) for project-wide constraints.
   - Read `CLAUDE.md` for project conventions (test framework, directory layout, naming conventions, etc.).
   - Load the test plan template from `$(git config kaba.scriptdir)/../templates/test-plan-template.md`. This defines the exact output structure.

3. **Identify the test directory**:
   - The test directory is `test_dir` in `.kaba/config.yml` — read it from there; never infer it from project structure.

4. **Survey the existing test suite**:
   - List all files in the test directory.
   - For files that might overlap with this feature, read their structure (test groups, test names, shared setup, factories/fixtures). This informs placement and granularity (steps 5–8) only — it is NOT how invalidated tests are discovered; that is step 9's sweep.
   - Note existing factories/fixtures, shared helpers, support files, and reusable modules.
   - Note the project's test file naming conventions and directory organization patterns.
   - Run `$(git config kaba.scriptdir)/snapshot-tests.sh identities` from the repo root and keep its output as a lookup artifact — the identity listing (address + description + file for every example in the current suite). On a large suite, write it to a scratch file and query it per address instead of holding it whole.
   - Derive the **contract-delta list** per the **Invalidation Sweep Rules** below: every observable behavior this feature changes (as opposed to adds), recorded as CD-1, CD-2, … with the old contract, the new contract, and its source. A purely additive feature records "no contract deltas" explicitly.

5. **Design test file structure**: Apply the Criteria-to-File Mapping Rules below to assign every criterion to a test file. Decide which test layer/directory a behavior maps to via the **same placement order of authority** as step 3 (`architecture.md` → existing project/test conventions → framework default). If shaping a test (its layer, structure, or what it must assert) would require a production-code structural fact that isn't established, STOP and escalate immediately per **Resolution Chain & Escalation**.

6. **Identify factory needs**: Apply the Factory Rules below for every entity referenced in the acceptance criteria.

7. **Identify shared helpers**: Apply the Shared Helper Rules below for repeated patterns across test files.

8. **Map criteria to files**: Produce the Criteria Mapping table. Every criterion ID from the acceptance criteria document MUST appear in exactly one row.

9. **Run the invalidation sweep**: Apply the **Invalidation Sweep Rules** below to every contract delta from step 4 — derive probes, run them as content searches over the entire test directory, resolve hits to examples via the step-4 identity listing, and disposition every hit example as KEEP, MODIFY, or REMOVE. Record probes, hits, and dispositions for the plan's Invalidation Sweep section. If step 4 recorded no contract deltas, record that and continue.

10. **Plan state changes**: Derive the Planned State Changes table from the step-9 dispositions: every MODIFY/REMOVE disposition becomes a row — action, identity, description (both copied from the step-4 identity listing, never composed from reading spec source), and reason. A row may also arise outside the sweep (an existing example changing for a reason other than a contract delta, e.g. extended to cover a new criterion); each such row carries its own reason traceable to the spec. File-level (MODIFY) markings in Test File headings must agree with this table: a file marked MODIFY has at least one MODIFY row; a file with MODIFY rows is marked MODIFY.

11. **Self-validate the plan**: Run every check in the Validation Checklist below. If any check fails, fix the plan before proceeding. Do NOT silently skip failures.

12. **Write the test plan document**: Fill in the loaded template and output to `FEATURE_DIR/test-plan.md`. Then generate `FEATURE_DIR/test-plan.json` from the Planned State Changes table — always, even when the table is "None":

    ```json
    {
      "version": 2,
      "feature": "[feature dir name]",
      "source": "test-plan.md",
      "entries": [
        {"action": "MODIFY|REMOVE", "id": "[identity]", "file": "[file path]",
         "description": "[recorded description]"}
      ]
    }
    ```

    An empty `entries` array is an affirmative statement: this plan declares no modifications and no removals. The JSON is machine-written by this command, whole, on every run.

13. **Report**: Print a summary with format validation (see Report Format below).

## Resolution Chain & Escalation

`plan-tests` makes **no** architectural or library decisions. When it needs a fact to place or shape a test, it resolves it from existing sources; if the fact is not there and is genuinely required, it stops and asks.

### Resolution chain

This is distinct from the **placement order of authority** (steps 3 & 5): that decides *where* tests go and always has a framework default to fall back on. The resolution chain instead decides whether a needed *production-code fact* exists at all — and if it does not, the stop test below applies.

Look for the needed fact in this order: **`.kaba/architecture.md` → project rules → an answer the human gave inline (conversation or this command's arguments)**. `research-log.md` is NOT part of this chain — it is a human-facing aid, not a command input. If the fact is found, use it and proceed.

### What counts as an architectural decision (never invented here)

A decision about the **existence or shape of production-code structure, technology, or a cross-cutting pattern that is not yet established** — a new layer, a new dependency that owns a concern, or a new paradigm (async/jobs, websockets, PDF generation). `plan-tests` never decides one of these.

### What `plan-tests` decides freely (its autonomy)

All test-suite **organization**: which file a criterion lands in, factory/trait design, shared-helper extraction, describe-block structure, and applying **already-established** layer→test-layer mappings. These are governed by this command's own rules plus existing test conventions — never escalate for them.

### The stop test (one line)

> Does writing this behavior test require deciding a structural or technological fact about production code that is not in `architecture.md` / project rules (or given inline)? If **yes** → STOP. If the behavior is assertable at the boundary, or it is pure test-organization → PROCEED.

### Behavioral-boundary principle

`plan-tests` plans **behavior** tests, and behavior is usually observable at the boundary without knowing the implementation. So most implementation/architectural unknowns do NOT block it.

- **Does NOT stop:** a feature generates PDFs. The test asserts `POST /reports` returns `200` with `Content-Type: application/pdf`. *Which* PDF library is irrelevant to the test — that is `plan-code`'s decision later. Proceed.
- **Stops:** a feature processes files and notifies the user "later." Tested as a synchronous request, or by asserting a **job is enqueued**? If no async/job pattern is established, the test's own structure depends on a production-code fact that does not yet exist. Stop.

### On stop — the escalation block

Halt before writing the test plan and emit exactly this, listing every unresolved question:

```
## Escalation — input needed

plan-tests cannot complete without the following. Each blocks goal (1) behavior tests or (2) alignment with existing architecture.

1. [The unresolved question, stated concretely.]
   - Why it blocks: [which test(s) can't be shaped, and why the answer isn't in architecture.md / project rules]

[repeat per question]

No test plan was written. Re-run /kaba:plan-tests once the answer is available.
```

Do NOT prescribe how the human should resolve it. The human may answer inline, document it (e.g. in `CLAUDE.md`) if they judge it a durable convention, or run `/kaba:research` for help deciding — their call. A re-run is stateless: it resolves the fact through the chain above (or from an inline argument) and continues.

### Amendment re-runs

A re-run may carry an `## ESCALATION — test-plan defect` block from `implement-tests` or `fix-tests` as input. Treat it as scope: re-scan identities (step 4), re-run the invalidation sweep (step 9) for any contract delta the escalation touches, amend the affected plan sections and the Planned State Changes table, re-validate, and regenerate `test-plan.json` whole. Do not restructure parts of the plan the escalation does not touch.

An amendment re-run still passes through step 1's prior-run gate — the plan files exist, so it will ask. That is expected, not an error state: the amendment regenerates `test-plan.json` whole, so the previous version really is being destroyed. Answer the gate, mention the escalation as the reason, and continue.

## Criteria-to-File Mapping Rules

**CRITICAL**: Every criterion from the acceptance criteria document MUST be assigned to exactly one test file. No criterion may be left unmapped. No criterion may appear in more than one file.

> Examples below use generic paths for illustration. Use your project's actual conventions for paths, extensions, and naming.

### How to assign criteria to files

1. **Same acceptance criteria category → same test file**, unless the category spans multiple test layers (e.g., a category that mixes model validations with request-level behavior should be split by layer).

2. **Test layer determines the directory**. Follow the project's existing directory conventions. If no conventions exist, use the test framework's standard layout:
   - Model/entity behavior and validations → `tests/models/` or `tests/unit/`
   - HTTP request/response → `tests/requests/` or `tests/integration/`
   - End-to-end → `tests/e2e/`
   - Support/helpers → `tests/support/` or `tests/helpers/`

3. **One entity or endpoint per file**. Do not combine multiple unrelated entities or endpoints in a single test file.

4. **Cross-cutting criteria** (e.g., authentication, response format) that are tested at the request level: group by the concern, not by the endpoint. One authentication test file, not auth tests scattered across each endpoint file.

5. **If the project already has test files**, match their granularity. If existing tests cover one model per file, continue that pattern. If existing tests group related models, continue that pattern.

### Examples

- ✅ CORRECT: All model validation criteria for entity X → `tests/models/x_test` (same entity, same layer)
- ✅ CORRECT: All authentication criteria → `tests/requests/authentication_test` (cross-cutting concern, one file)
- ✅ CORRECT: All create-endpoint criteria → `tests/requests/items/create_test` (one endpoint per file)
- ✅ CORRECT: All scoping criteria → `tests/requests/items/scoping_test` (cross-cutting concern across endpoints)
- ❌ WRONG: `VAL-001` in both a model test AND a request test (criterion in two files)
- ❌ WRONG: Create, update, and delete criteria all in one file (multiple endpoints in one file — too coarse)
- ❌ WRONG: `AUTH-001` in the create test, `AUTH-002` in the list test, `AUTH-003` in the show test (cross-cutting concern scattered across endpoint files)
- ❌ WRONG: Model-behavior criteria tested in a request test (wrong layer)

## Factory Rules

"Factory" means any test data setup mechanism the project uses: factories, fixtures, builders, seed helpers, etc. Use the project's own terminology and conventions.

> Examples below use generic paths for illustration. Use your project's actual conventions for paths, extensions, and naming.

### How to identify factory needs

1. **One factory per entity** referenced in the acceptance criteria. If the entity already has a factory, mark it EXISTS.

2. **Traits/variants for variations**. Each distinct setup pattern the criteria need becomes a trait or variant. Name them after what they produce, not what test uses them.

3. **Associations are explicit**. If factory A needs factory B, list it. Do not rely on implicit creation.

### Examples

- ✅ CORRECT:
  ```
  ### order (NEW)

  - **File**: tests/factories/orders
  - **Base attributes**: total (sequential integer), status ("pending"), customer (association)
  - **Traits/variants**:
    - completed — sets status to "completed"; for criteria testing completed-order behavior
    - high_value — sets total to 10,000; for boundary testing on value thresholds
  - **Associations**: customer factory
  - **Used by**: tests/models/order_test, tests/requests/items/create_test
  ```
- ❌ WRONG:
  ```
  ### Order factory

  - **Status**: NEW
  - **Traits**: various status traits
  - **Notes**: will need some traits for edge cases
  ```
  (Missing file path, missing base attributes, vague trait descriptions, no associations, no used-by list)

## Shared Helper Rules

"Shared helper" means any reusable test setup, assertion, or utility extracted to avoid duplication: shared contexts, mixins, helper modules, custom assertions, etc. Use the project's own terminology and conventions.

> Examples below use generic paths for illustration. Use your project's actual conventions for paths, extensions, and naming.

### When to create a shared helper

1. **3+ test files** use the same setup or assertion pattern → MUST extract to a shared helper.
2. **2 test files** use the same pattern → use judgment; extract if the pattern is complex.
3. **1 test file** → do NOT extract. Inline it.

### Examples

- ✅ CORRECT:
  ```
  ### JSON response helper (NEW)

  - **File**: tests/support/json_helpers
  - **Type**: helper_method
  - **Purpose**: Parses response body as JSON and provides accessor for nested keys.
  - **Interface**: `json_response()` returns the parsed response body as a dictionary/hash
  - **Used by**: tests/requests/items/create_test, tests/requests/items/list_test, tests/requests/items/show_test, tests/requests/items/update_test
  ```
- ❌ WRONG:
  ```
  ### Response helper

  - **Status**: NEW
  - **Purpose**: Help with responses in tests
  - **Used by**: multiple request tests
  ```
  (Missing file path, missing type, missing interface, vague purpose, vague used-by)

## Test File Entry Examples

> Examples below use generic paths for illustration. Use your project's actual conventions for paths, extensions, and naming.

- ✅ CORRECT:
  ```
  ### tests/models/order_test (NEW)

  - **Criteria**: VAL-001, VAL-002, VAL-003, VAL-004, CALC-001, CALC-002, CALC-003, OWN-001, OWN-002
  - **Describe blocks**:
    - `Order`
      - `validations`
        - `total` — covers: VAL-001, VAL-002, VAL-003
        - `status` — covers: VAL-004
      - `calculations`
        - `tax computation` — covers: CALC-001, CALC-002, CALC-003
      - `associations`
        - covers: OWN-001, OWN-002
  - **Dependencies**: order factory, customer factory
  ```
- ❌ WRONG:
  ```
  ### tests/models/order_test (NEW)

  - **Status**: NEW
  - **Criteria**: VAL-001 through VAL-004, CALC-001 through CALC-003
  - **Describe blocks**: validations, calculations, associations
  - **Notes**: Standard model test
  ```
  (Criteria ranges instead of explicit IDs, describe blocks without nesting or criterion mapping, no dependencies)

## Invalidation Sweep Rules

The Planned State Changes table is only as good as the discovery behind it. Discovery is a mechanical, suite-wide **content sweep** anchored on contract deltas — never an association from file names or topics ("this file sounds related"). A file's name says what it is about; only its content says what it exercises.

### Contract deltas

A **contract delta** is an observable behavior that exists in the current codebase and that this feature **changes** — as opposed to behavior it merely adds:

- an endpoint's response status, body shape, or headers;
- an action's semantics — what it persists, destroys, or schedules;
- a visibility or scoping rule — what listings include, what lookups find;
- a resource representation — attributes added, removed, or renamed;
- an error contract — the status or envelope for a given failure.

Sources: spec language phrased as change ("instead of", "no longer", "stop …ing", "becomes"), the acceptance criteria, and clarifications. Purely additive behavior is NOT a delta — no existing test can assert about what doesn't exist yet — with one exception: check new routes/names against existing negative guards (e.g. "this route does not exist" examples).

Each delta is recorded as CD-1, CD-2, … with the old contract, the new contract, and its source (FR / criterion / clarification).

A delta is **conditional** if old and new behavior differ only when some state exists (e.g. "listings exclude trashed bookmarks" — differs only when a trashed bookmark exists); otherwise it is **unconditional** (e.g. "delete now answers 204 with an empty body" — every delete call site is affected).

### Probes

For each delta, derive **probes**: the concrete strings an existing test would contain if it exercises the delta's surface, at BOTH boundaries:

- **request boundary**: the HTTP verb + path fragment (e.g. `delete "/api/v1/bookmarks`), route-recognition assertions naming the controller#action;
- **storage/behavior boundary**: assertions whose truth the delta flips — model existence/count checks (e.g. `Bookmark.exists?`), attribute reads after the changed action, names of attributes or enum values whose meaning changes.

Probes err broad. Over-matching costs a disposition line; under-matching recreates exactly the defect this sweep exists to prevent.

### The sweep

1. Run every probe as a content search over the ENTIRE test directory. Never restrict the search to files whose names relate to the feature.
2. Resolve each hit line to its enclosing example via the identity listing (address + description).
3. Disposition every hit example, exactly one of:
   - **KEEP** — still passes under the new contract. Lawful only with a stated one-line reason ("refused delete leaves the record active; `exists?` still true"). An example that reads the response of a changed endpoint, or asserts a post-condition the delta touches, can never be KEEP by default.
   - **MODIFY** — must change to hold under the new contract; becomes a MODIFY row in Planned State Changes.
   - **REMOVE** — asserts the old contract and has no valid new-contract form; becomes a REMOVE row.
4. Record the sweep in the plan's Invalidation Sweep section: per delta — the probes used, the files hit, and the disposition table (address, description, disposition, reason).

### Scale rules

The sweep's cost is proportional to the change's blast radius (hits), never to suite size — keep it that way:

1. **Search-driven, never enumerate-and-read.** The suite is swept by content search; example bodies are opened only for hits the cheaper levels below cannot decide.
2. **Triage ladder.** Decide each hit at the cheapest sufficient level: hit line plus a few context lines → the full example → the full file. Stop at the first level that decides.
3. **Collective KEEP.** For a conditional delta, hits in a file that never performs the state-entering action (no probe for it co-occurs anywhere in the file) may be dispositioned KEEP collectively, one line per file, with the shared reason. Unconditional deltas get example-level dispositions at every hit — no exceptions.
4. **Batch fan-out.** When more than ~30 hits need example-level reads, disposition them in parallel batches via subagents: each batch gets hit addresses, reads only those examples, and returns disposition rows; the plan records the merged table identically.
5. **Identity listing as lookup.** On a large suite, query the identity listing per address; do not hold it whole.

### Examples

- ✅ CORRECT: delta "standard delete: 200 + data envelope + destroys → 204 + empty body + moves to trash" (unconditional) → probe `delete "/api/v1/bookmarks` over the whole test directory → hits in the destroy, response-format, authentication, pagination, scoping, and out-of-scope files → every hit example dispositioned; the response-format file's delete-response assertions become MODIFY/REMOVE rows even though the file is "about" response format, not deletion.
- ❌ WRONG: the same delta "discovered" by reading the destroy file because its name matches the topic — the response-format file's delete-response assertions are never found, the plan ships incomplete, and the locked suite becomes unsatisfiable: those examples parse a response body the new contract leaves empty, so no implementation can green both them and the new delete tests.
- ❌ WRONG: dispositioning a hit "KEEP — probably fine" with no reason, or skipping hits in a file because "it's about something else".

## Validation Checklist

Before writing the plan document, verify ALL of the following. If any check fails, fix the plan first.

1. **Complete coverage**: Every criterion ID from acceptance-criteria.md appears in exactly one test file's Criteria list. Count them — the total MUST equal the acceptance criteria Summary total.
2. **No duplicates**: No criterion ID appears in more than one test file's Criteria list.
3. **No empty files**: Every test file listed covers at least one criterion.
4. **Describe blocks map to criteria**: Every criterion ID in a file's Criteria list appears in exactly one `covers:` line in that file's Describe blocks section.
5. **Factory completeness**: Every factory referenced in any test file's Dependencies list appears in the Factories section with status NEW, MODIFY, or EXISTS.
6. **Helper completeness**: Every shared helper referenced in any test file's Dependencies list appears in the Shared Helpers section.
7. **Used-by consistency**: Every test file that lists a factory or helper in Dependencies appears in that factory/helper's Used-by list, and vice versa.
8. **Path conventions**: All file paths use the project's actual naming conventions, extensions, and directory layout.
9. **Criteria Mapping table matches**: The Criteria Mapping table at the end is a 1:1 match with the per-file Criteria lists — same criterion, same file, no discrepancies.
10. **State-change entries resolve**: Every Planned State Changes row's identity exists in the step-4 identity listing (a group address must match at least one example), and its description equals the listing's recorded description byte-for-byte (for a group address: every matched example's description starts with it). A row that fails is a plan error — fix it from the listing, never by editing the string freehand.
11. **MODIFY consistency**: Test File headings marked MODIFY and the Planned State Changes table agree in both directions.
12. **Removal reasons**: Every REMOVE row has a concrete reason traceable to the spec.
13. **Delta completeness**: Every spec statement phrased as a change to existing behavior maps to a contract delta, and every delta has at least one request-boundary probe plus, where semantics change, at least one storage-boundary probe.
14. **Sweep coverage**: Every probe was run over the entire test directory, and every hit example carries exactly one disposition — none silently dropped.
15. **Disposition–table consistency**: Every MODIFY/REMOVE disposition has a matching Planned State Changes row, and every row either traces to a disposition or carries its own reason.
16. **KEEP satisfiability**: No KEEP disposition's reason contradicts any delta's new contract — a KEEP that asserts the old contract is a plan error.

## Report Format

If the command stopped to escalate (during placement, steps 3–5), the only output is the escalation block from **Resolution Chain & Escalation** — do NOT print the summary below, and do NOT write a test plan.

Otherwise the report MUST include:

```
## Summary
- Test files: [N] ([N] new, [N] modify, [N] existing)
- Factories: [N] ([N] new, [N] existing)
- Shared helpers: [N] ([N] new, [N] existing)
- Criteria mapped: [N] / [N] (MUST be equal — if not, ERROR)
- Contract deltas: [N]
- Invalidation sweep: [N] examples hit — [N] keep / [N] modify / [N] remove

## Validation
- [ ] Complete coverage: [PASS/FAIL]
- [ ] No duplicates: [PASS/FAIL]
- [ ] No empty files: [PASS/FAIL]
- [ ] Describe blocks map to criteria: [PASS/FAIL]
- [ ] Factory completeness: [PASS/FAIL]
- [ ] Helper completeness: [PASS/FAIL]
- [ ] Used-by consistency: [PASS/FAIL]
- [ ] Path conventions: [PASS/FAIL]
- [ ] Criteria Mapping table matches: [PASS/FAIL]
- [ ] State-change entries resolve: [PASS/FAIL]
- [ ] MODIFY consistency: [PASS/FAIL]
- [ ] Removal reasons: [PASS/FAIL]
- [ ] Delta completeness: [PASS/FAIL]
- [ ] Sweep coverage: [PASS/FAIL]
- [ ] Disposition–table consistency: [PASS/FAIL]
- [ ] KEEP satisfiability: [PASS/FAIL]
```

If ANY validation check is FAIL, do NOT proceed. Fix the plan and re-validate.

## Key Rules

- **Every criterion must be mapped.** If a criterion from the acceptance criteria document does not appear in the plan, the plan is incomplete. ERROR.
- **No test code.** Not even pseudocode. Describe blocks define organizational structure, not assertions or setup code.
- **Follow existing conventions.** If the project already has test files, match their naming, directory layout, and organizational patterns. Do NOT impose a new structure.
- **Factories are first-class.** Every entity that needs test data MUST have a factory in the Factories section. Do NOT assume factories will be created ad-hoc during implementation.
- **Shared helpers reduce duplication.** 3+ files with the same pattern → MUST extract. 2 files → use judgment. 1 file → do NOT extract.
- **The plan is a contract.** The implement-tests step will follow this plan exactly — file paths, criterion mapping, factory names, describe block structure. Changes after this point require re-planning.
- **Flag, don't guess.** If an organizational decision depends on an implementation detail not yet known *but the behavior is still testable at the boundary*, add a `**Notes**` field to the affected entry explaining the uncertainty and proceed. Do NOT silently pick an option. (But if the unknown actually blocks shaping a behavior test — a not-yet-established architectural fact — STOP and escalate instead; see **Resolution Chain & Escalation**.)
- **Use the project's language and conventions.** All file paths, extensions, naming patterns, and terminology MUST match what the project actually uses. Do NOT default to any specific language or framework.
- **Make no architectural or library decisions.** Plan only the two goals — behavior tests and alignment with existing architecture. If a placement or structure decision needs a not-yet-established production-code fact, STOP and escalate per **Resolution Chain & Escalation**. Test at the behavioral boundary so implementation unknowns (e.g. which library) do NOT block planning.
- **Invalidation is swept, not guessed.** Existing tests affected by the feature are discovered by suite-wide content probes derived from contract deltas (see **Invalidation Sweep Rules**); every hit is dispositioned KEEP/MODIFY/REMOVE. A file's name never decides whether it is searched — only its content says what it exercises.
- **test-plan.json is generated, whole, always.** It is the mechanical twin of the Planned State Changes table, emitted on every run (empty is valid and meaningful). No other command or person ever writes it.