---
name: research
disable-model-invocation: true
description: Investigate a single open question for the current feature given this project's stack, and append a short recommendation to research-log.md for the human to decide on. Human-facing decision support — no other command reads its output.
handoffs:
  - label: Resume Test Planning
    agent: kaba:plan-tests
    prompt: 'Resume test planning. My decision: <state it here before sending>'
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding. It states the question or topic to investigate. If it is empty, ERROR and stop — ask the user what to research.

## Purpose

`/kaba:research` helps the **human** decide an open question that a planning command could not resolve (typically a new technology or paradigm: PDF generation, async processing, websockets). It investigates the question **given this project's stack** and writes a short, concrete recommendation.

It is **decision support**, not a decision authority and not a command input. The human reads the recommendation and decides; they then feed that decision back to planning (inline, or by documenting it). **No command reads `research-log.md`** — nothing downstream depends on it. The decision reaches the architecture doc later, via `/kaba:architecture-diff` capturing the implemented pattern from code reality (not triggered by this command).

## Outline

1. **Resolve feature paths**: Run `$(git config kaba.scriptdir)/resolve-feature.sh` from the repo root. It prints three `KEY=value` lines — `REPO_ROOT`, `FEATURE_DIR`, `FEATURE_SPEC` — read them line-by-line (never `eval`; a path may contain spaces). ERROR and stop if the script exits non-zero or `FEATURE_DIR` is absent from its output.
2. **Load stack context and the template**:
   - Read `CLAUDE.md` for the declared stack and conventions.
   - Read `.kaba/architecture.md` (if present) for current structure and existing patterns.
   - Read the dependency manifest(s) present (Gemfile / package.json / pyproject.toml / go.mod / …) for what is already available.
   - Load the entry structure from `$(git config kaba.scriptdir)/../templates/research-template.md`. This defines exactly what each `research-log.md` entry must contain.
3. **Decide source scope** per the Research Method below: determine whether the question is in a fast-moving domain (→ web search will be required in step 4) or a mature, stable one (→ stack knowledge and codebase only, no search). This is your own judgment — never escalate for it.
4. **Investigate the question** using the selected sources, given this stack. Evaluate the realistic options against the weighted dimensions in the Research Method (with the proven-technology bias). Do this reasoning in your working context — it is NOT written to the file.
5. **Choose a recommendation**: pick the single option best fitting this stack. Identify the alternatives you rejected, the one-line reason each lost, and a link for each where one exists.
6. **Append to `FEATURE_DIR/research-log.md`** the filled template as one new entry. If the file does not exist, create it with this entry; if it exists, add the entry at the end, separated from the previous one by a horizontal rule (`---`). NEVER overwrite, edit, or delete earlier entries — the file is an append-only log, one entry per run. Set **Basis** to the sources you actually consulted (note whether web search was done; include the links). Keep the entry short — no investigation transcript.
7. **Report**: print the recommendation in one or two sentences and remind the human that they decide — they can answer planning inline, document the decision, or adjust and re-run.

## Research Method

### Source selection — proportional to domain volatility

Project sources are ALWAYS in scope: the codebase, `CLAUDE.md`, `architecture.md`, the project rules, the dependency manifest. Beyond that, choose per question:

- **Fast-moving / recency-sensitive domain** (anything AI/LLM-related, fast-churning ecosystems) → **web search is required**: your training knowledge is likely stale and the best option may have changed in months.
- **Mature, stable domain** (PDF generation, CSV processing — settled for years) → **no web search**; stack knowledge plus the codebase is enough. Searching would only burn tokens.

The heuristic: *would current information materially change the answer? If yes, search; if it is a settled domain, do not.* This is your own judgment — never escalate for it.

### Evaluation — weighted toward proven technology

Weigh options by: **fit with the existing stack/deps** (reuse what is there) · **maturity & maintenance** (stable for years, actively maintained) · **community adoption & ecosystem** (widely used, well-documented) · **simplicity for the actual need** (no over-engineering).

**Bias: lean to the stable, proven, community-backed option. Treat "very new / hype-driven" as a red flag** — something hyped today can be abandoned in months, and this recommendation must not steer the project onto a fad. Even when web search surfaces a hot new library, default to the boring, well-supported choice unless there is a compelling, durable reason.

## Key Rules

- **Recommend, do not menu.** Output ONE concrete recommendation, not a list of equally-weighted options. The human ratifies; they should not have to do the weighing.
- **Ground it in this stack.** A recommendation that ignores the project's existing dependencies, conventions, and architecture is useless. Read them first.
- **Match the source to the domain.** Web search for fast-moving domains; skip it for settled ones. Record what you consulted in the **Basis** line.
- **Bias to proven.** New and hyped is a risk, not a selling point. Favor mature, well-supported options.
- **Fill the template; keep the entry short.** Use `$(git config kaba.scriptdir)/../templates/research-template.md` — Basis, Recommendation + rationale, Rejected Alternatives (with links where available). The investigation/reasoning stays in your working context, NOT in the file.
- **The human is the consumer.** No command reads `research-log.md`. Do not write it as machine input; write it for a person deciding.
- **Feature-scoped.** It lives at `FEATURE_DIR/research-log.md` and concerns only this feature.
- **Append-only log.** One entry per run, newest last, separated by `---`. Never overwrite or rewrite earlier entries — they may record recommendations the human has already ratified. The filename is deliberate: `research.md` is the filename other spec-driven workflows commonly use in the same feature directory for a different purpose — never write that filename, only `research-log.md`.
