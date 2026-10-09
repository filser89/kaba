---
name: specify
disable-model-invocation: true
description: Author or import a feature specification — scaffold the branch and feature directory via new-feature.sh, then fill kaba's spec template, never inventing requirements the user did not state.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding. It is either a one-liner describing the
feature, or `--spec <path>` naming an existing document to import. If empty, ERROR and stop — ask
the user for a one-liner or a `--spec` path.

## Purpose

`/kaba:specify` is the pipeline's entry point. It turns a feature description into `spec.md`,
inside a freshly scaffolded, numbered feature directory on a freshly scaffolded branch. It never
invents requirements: only what the user stated — or what an imported document states — reaches the
spec. Anything the author could not settle goes under Open Questions, which `/kaba:clarify` works
down to empty next.

## Outline

0. **Prior-run gate — before scaffolding anything.** Run
   `$(git config kaba.scriptdir)/check-artifacts.sh specify` from the repo root and read its
   `KEY=value` lines. This command never overwrites a file; its hazard is different. `new-feature.sh`
   allocates the **next** number and branches off whatever is currently checked out, so an accidental
   re-run silently creates a stray feature hanging off the current one. The gate therefore keys on
   whether a feature resolved at all, not on whether `spec.md` exists.
   - `PRIOR_RUN=unknown` with `REASON=no-feature-branch` — this is the normal fresh start. Proceed.
   - `PRIOR_RUN=yes` — you are already on a feature branch. STOP and ask, using `FEATURE_DIR` and
     `MISSING` to say which case it is: if `MISSING=spec.md`, a previous `/kaba:specify` did not
     finish — offer to resume it by writing the spec into the existing directory instead of
     scaffolding a new one. Otherwise the feature is complete, and continuing will create a **new**
     numbered feature branched off this one. Ask which they want, then **end your turn** — do not
     answer yourself and do not proceed in the same response. Use `AskUserQuestion` if available.
   - A non-zero exit, or no `PRIOR_RUN=` line at all — STOP and report the script's stderr verbatim.
     **Absence of an answer is never "no."**

1. **Determine mode**: if `$ARGUMENTS` starts with `--spec `, this is **import mode** and the rest
   of the argument is the source document's path; otherwise this is **author mode** and the whole
   argument is the one-liner. In import mode, if the path does not exist, ERROR and stop.

2. **Derive the slug**: lowercase the source text, collapse every run of non-alphanumeric
   characters to a single hyphen, trim leading/trailing hyphens, and keep at most the first four
   words. In author mode the source text is the one-liner; in import mode it is the source
   document's filename without its extension.

3. **Scaffold via the script — never by hand**: run
   `$(git config kaba.scriptdir)/new-feature.sh <slug>` from the repo root. It prints four
   `KEY=value` lines — `FEATURE_NUM`, `BRANCH`, `FEATURE_DIR`, `FEATURE_SPEC` — read them
   line-by-line (never `eval`; a path may contain spaces). ERROR and stop if the script exits
   non-zero. This script is the only thing that creates the branch or the feature directory — do
   not run `git checkout -b` or `mkdir` yourself under any circumstance.

4. **Load the template from the plugin, not the project**:
   `$(git config kaba.scriptdir)/../templates/spec-template.md`. This defines the sections `spec.md`
   must have and their order.

5. **Author mode — fill the template from the one-liner and the conversation with the user**:
   - Fill the template sections, including Delivery Obligations and Supporting Context, only with what the user actually stated or confirmed when asked.
   - Consequential choices the user did not settle go under Open Questions. Mark inapplicable or
     empty sections explicitly rather than treating every empty template slot as a question.
     Never invent requirements, scenarios, edge cases, delivery tasks, or success criteria.

6. **Import mode — map the source document onto the template's sections**:
   - Read the source document in full. For each template section, carry across the matching
     content (e.g. a requirements list → Functional Requirements; usage examples or Given/When/Then
     walkthroughs → Acceptance Scenarios; stated limits or explicit non-goals → Out of Scope).
   - Preserve known documentation, configuration examples, CI/setup verification, and completion
     tasks under Delivery Obligations with DO-NNN IDs, sources, and completion checks. Preserve
     relevant metadata, rationale, and side notes under Supporting Context. Only unresolved
     choices go under Open Questions. Runtime configuration behavior, security guarantees,
     deadlines, and real user-visible setup behavior remain in the behavioral sections.
   - Unresolved consequential choices stay under Open Questions. Mark empty/inapplicable sections
     explicitly; do not manufacture questions or requirements merely to fill the template.

7. **Write** the filled template to `FEATURE_SPEC`: `[name]` from the one-liner or the source
   document's title, `[NNN-slug]` set to `BRANCH`, `Status` left as `draft`. Before reporting, compare every supplied
   requirement, scenario, limitation, delivery task, and open question to its destination; preserve
   its meaning and specificity, and fix omissions or contradictions without inventing answers.

8. **Report**: the created branch, the feature directory, and the spec path. Then point the user at
   `/kaba:clarify` as the next step.

## Key Rules

- **Classify the obligation itself, not its heading or security label.** Split mixed supplied
  clauses by obligation while preserving their source and meaning: documentation, example/config
  packaging, tracked placeholders, ignored `.env` files, and version-control hygiene checks are
  Delivery Obligations, even inside a functional/security requirement. Runtime secret disclosure
  and security guarantees remain behavioral requirements. Preserve every clause without adding
  behavior.

- **Two modes, one flag.** Default is author-from-one-liner; `--spec <path>` switches to import.
  No other parameter threads through this command.
- **The script owns scaffolding.** Branch and feature-directory creation belong to
  `new-feature.sh` alone.
- **The template is the plugin's, not the project's.** Always resolve it via
  `$(git config kaba.scriptdir)/../templates/spec-template.md`.
- **Never invent.** Every requirement, scenario, edge case, and success criterion must trace to
  something the user said or the imported document stated. Unknowns go to Open Questions — closing
  that list is exactly what `/kaba:clarify` exists to do.
- **Nothing from an imported document is discarded.** Use Supporting Context for relevant facts without another home, Delivery Obligations for known
  deliverables, and Open Questions for unresolved choices. Preserve source references and any
  existing stable IDs; do not turn deliverables into invented behavioral tests.
