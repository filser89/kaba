---
description: Turn the locked test suite into an implementation plan — components, schema, decisions, and dependency-ordered build order to make every test green, consistent with existing architecture. No implementation code.
handoffs:
  - label: Implement Code
    agent: kaba:implement-code
    prompt: Implement the code following the implementation plan
    send: true
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). The user may provide additional constraints, focus areas, or corrections to scope.

## Purpose

This command takes the **locked test suite** (the contract) and the **spec** (the intent) and produces an implementation plan — the production-code structure and the test-invisible decisions needed to make every test green, consistent with the existing architecture and the project's rules. It is the mirror of `plan-tests`: `plan-tests` locked only the decisions a test can *see*; this command owns the decisions a test is *blind to*.

This is a **planning step**, not a writing step. No implementation code is produced — not models, controllers, services, migrations, or method bodies. The output is `code-plan.md`, which `/kaba:implement-code` will follow.

**This command has exactly one goal:** produce a plan that, when followed, turns the locked test suite green — structured consistently with the existing architecture (`architecture.md`) and the project's rules. It owns implementation and library decisions, but it does not make every such decision blindly: when a decision is **not safely defaultable**, it stops and asks the human — see **Resolution Chain & Escalation** below.

## Outline

1. **Resolve feature paths**: Run `$(git config kaba.scriptdir)/resolve-feature.sh` from the repo root. It prints three `KEY=value` lines — `REPO_ROOT`, `FEATURE_DIR`, `FEATURE_SPEC` — read them line-by-line (never `eval`; a path may contain spaces).
   - Identify the test directory (`test_dir` in `.kaba/config.yml` — read it from there, never infer it from project structure) and read the **locked test suite** — the contract. If no tests exist, ERROR and stop: this command runs after the test session.
   - Read the spec from `FEATURE_SPEC` — the intent. If it does not exist, ERROR and stop.

2. **Load context and template**:
   - Read `.kaba/architecture.md` — the existing patterns: the consistency reference and the resolution-chain source for "is this fact already established?". If absent or a bare greenfield skeleton, note that.
   - Read the project rules (CLAUDE.md/AGENTS.md, per `.kaba/config.yml`'s `rules_files`) — the rules the plan must obey (e.g. size limits, layering rules, naming and response-format conventions).
   - Do **NOT** read `acceptance-criteria.md` or `test-plan.md` — they are scaffolding absorbed into the locked tests.
   - Load `$(git config kaba.scriptdir)/../templates/code-plan-template.md` — the output structure.

3. **Survey the test suite and existing code**:
   - Read every locked test file: the behaviors asserted, the factories/setup used, the response shapes expected. This is the contract the plan must satisfy.
   - Survey existing production code for patterns to reuse and conventions to follow.

4. **Design components**: Decompose the behavior into production components, grouped by layer. For each, write its responsibility and map its **action/method-level sub-responsibilities to the test group it greens** (see **Altitude Rules**). Follow patterns already declared in `architecture.md`/the project rules — applying a declared pattern is not an escalation.

5. **Identify the data model**: Per persisted entity, the schema decisions the tests cannot see — columns, types, nullability, indexes, FKs, constraints.

6. **Make decisions**: For each test-invisible choice, apply the **Decision-Quality Procedure**. Before committing a choice, apply the **stop test** in **Resolution Chain & Escalation**. If a decision is not safely defaultable, STOP and escalate immediately.

7. **Determine build order**: A dependency-ordered sequence of the components — the task list for `implement-code`.

8. **Self-validate the plan**: Run every check in the **Validation Checklist**. Fix the plan before writing if any check fails. Do NOT silently skip failures.

9. **Write the plan**: Fill the loaded template and output to `FEATURE_DIR/code-plan.md`.

10. **Report**: Print the summary (see **Report Format**).

## Resolution Chain & Escalation

`plan-code` owns implementation and library decisions, but it does not invent facts that belong to the human. When a decision needs a fact, it resolves it from existing sources; when a decision is **not safely defaultable**, it stops and asks.

### Resolution chain

Look for the needed fact in this order: **`.kaba/architecture.md` → project rules → an answer the human gave inline (conversation or this command's arguments)**. If the fact is found, use it and proceed.

### What counts as an architectural decision

A decision about the **existence or shape of production-code structure, technology, or a cross-cutting pattern that is not yet established** — a new layer, a new dependency that owns a concern, or a new paradigm (async/jobs, websockets, file storage, PDF generation).

### The stop test — "safely defaultable"

A decision is **safely defaultable** when ALL THREE hold:

1. **Swappable later cheaply** — replacing it does not ripple through the codebase.
2. **Needs nothing external the human owns** — no cloud account, paid service, credentials, or vendor lock-in.
3. **Sets no undeclared pattern** — it does not establish a new layer / dependency-owning-a-concern / paradigm that is not already declared in `architecture.md` / the project rules.

If all three hold → **decide and flag** the choice in the Decisions section. If **any** fails → **STOP and escalate**. The two failure modes are *pattern-setting* (a new, undeclared architectural pattern) and *external commitment* (the answer lives in the human's environment, not the repo).

> A large architectural **delta** is NOT the same as an escalation. Establishing the model/controller/service layers on a greenfield project applies patterns already **declared** in the project rules — declared patterns are *applied*, not escalated. Escalation fires only for a pattern that is new **and** undeclared **and** not safely defaultable.

### Examples

- **Does NOT stop:** choosing a PDF library (Prawn/Grover) used inside one service — swappable, needs nothing external, sets no pattern. Decide + flag.
- **Stops (external commitment):** picking S3 vs GCS — the answer is a fact about the human's infrastructure (which cloud account they own), and guessing wrong wastes the implementation. Escalate.
- **Stops (pattern-setting):** this feature is the first to need file storage and no storage pattern is declared — it would establish a new dependency owning a concern. Escalate.

### On stop — the escalation block

Halt before writing the plan and emit exactly this, listing every unresolved question:

```
## Escalation — input needed

plan-code cannot complete without the following. Each blocks an implementation decision that is not safely defaultable.

1. [The unresolved decision, stated concretely.]
   - Why it blocks: [which component/decision can't proceed, and why the answer isn't in architecture.md / project rules]
   - Type: [pattern-setting | external commitment]

[repeat per question]

No implementation plan was written. Re-run /kaba:plan-code once the answer is available.
```

Do NOT prescribe how the human should resolve it. The human may answer inline, document it (e.g. in `CLAUDE.md` or `architecture.md`) if they judge it a durable convention, or run `/kaba:research` for help deciding — their call. A re-run is stateless: it resolves the fact through the chain above (or from an inline argument) and continues.

## Decision-Quality Procedure

For every non-trivial decision it owns, `plan-code` follows this motion:

1. **Name the driving constraints** — pulled from the spec and the tests, not assumptions.
2. **Investigate the determinable facts** — resolve what is knowable rather than guessing. Read the code, the dependency manifest, `architecture.md`, the tests; inspect inputs where relevant. Only genuinely un-groundable facts stay open. This same pass is the **escalation detector**: a fact that cannot be grounded here (external or pattern-setting) triggers the stop test.
3. **Eliminate by constraint, and name the trap** — state the plausible-but-wrong default explicitly and why it loses.
4. **Pick, with the trade-off and the flip-point** — when the choice would change.
5. **Record it** in the Decisions section (the verdict as a directive; the reasoning beneath).

## Altitude Rules

- Decide **which components exist, each one's responsibility, and the collaboration between them** (the internal seams the tests can't see). Map each component's **action/method-level sub-responsibilities to the test group it greens** — the analog of the test plan's describe→criteria mapping.
- Do **NOT** enumerate every method or every return value. Touch a method-level interface only for a **primary public seam that is a genuine design choice** (e.g. a service returning the record vs a Result object).
- Write **no** method bodies and **no** logic. The tests pin the observable interface; private decomposition and helper internals are `implement-code`'s job, bounded by the runnable suite.
- Schema details (columns, types, indexes, FKs, constraints) **ARE** in scope — they are invisible to the tests and must be decided here.

## Validation Checklist

Before writing the plan document, verify ALL of the following. If any check fails, fix the plan first.

1. **Test coverage**: Every locked test file maps to at least one component whose Greens list cites it. No test file is left without a code path.
2. **Greens consistency**: Every component's Greens entries reference test groups that exist in the locked suite.
3. **Schema completeness**: Every entity a component persists or reads has a Data Model entry.
4. **Decisions grounded**: Every entry in Decisions names its driving constraints and (where applicable) the rejected trap — no bare verdicts.
5. **No escalation left silent**: Any not-safely-defaultable decision is escalated, not guessed. If escalating, the only output is the escalation block.
6. **Rules respected**: The planned components respect the project rules (layering rules, size limits, and any other declared constraints are feasible).
7. **No implementation code**: The plan contains structure (names, responsibilities, schema) — no method bodies or logic.
8. **Build order complete**: Every component appears in the Build Order, dependency-ordered.

## Report Format

If the command stopped to escalate (step 6), the only output is the escalation block from **Resolution Chain & Escalation** — do NOT print the summary below, and do NOT write a plan.

Otherwise the report MUST include:

```
## Summary
- Components: [N] (by layer: [...])
- Entities (Data Model): [N]
- Decisions: [N] flagged
- Architectural delta: [new patterns/layers/deps, or "none — reuses existing patterns"]
- Test files covered: [N] / [N] (MUST be equal — if not, ERROR)

## Validation
- [ ] Test coverage: [PASS/FAIL]
- [ ] Greens consistency: [PASS/FAIL]
- [ ] Schema completeness: [PASS/FAIL]
- [ ] Decisions grounded: [PASS/FAIL]
- [ ] No escalation left silent: [PASS/FAIL]
- [ ] Rules respected: [PASS/FAIL]
- [ ] No implementation code: [PASS/FAIL]
- [ ] Build order complete: [PASS/FAIL]
```

If ANY validation check is FAIL, do NOT proceed. Fix the plan and re-validate.

## Key Rules

- **One goal: turn the locked tests green, consistently.** Plan only the production code + decisions needed for that. Do not re-decide anything the tests already pin.
- **No implementation code.** Not models, controllers, services, migrations, or method bodies. Structure and decisions only.
- **The tests are the contract; the spec is the intent.** Tests say what must hold; the spec says why, which grounds the flagged decisions.
- **Own implementation decisions; escalate the unsafe ones.** Decide freely when a choice is safely defaultable; STOP and escalate when it is pattern-setting or externally-committing. See **Resolution Chain & Escalation**.
- **Apply declared patterns, don't escalate them.** A new layer that follows a project-rules-declared convention is applied, not escalated. Escalation is for new + undeclared + unsafe decisions only.
- **Ground every decision.** Investigate determinable facts; never guess what is knowable. The same investigation surfaces what must be escalated.
- **The plan is a contract.** `implement-code` follows it — components, schema, decision verdicts, build order. Changes after this point require re-planning.
- **Use the project's language and conventions.** All paths, naming, and terminology MUST match what the project actually uses.
