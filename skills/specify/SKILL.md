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
   - Fill Summary, Acceptance Scenarios, Edge Cases, Functional Requirements, Success Criteria, and
     Out of Scope only with what the user actually stated or confirmed when asked.
   - Anything a section needs but the user did not state goes under Open Questions instead — never
     invent a requirement, a scenario, an edge case, or a success criterion to fill a gap.

6. **Import mode — map the source document onto the template's sections**:
   - Read the source document in full. For each template section, carry across the matching
     content (e.g. a requirements list → Functional Requirements; usage examples or Given/When/Then
     walkthroughs → Acceptance Scenarios; stated limits or explicit non-goals → Out of Scope).
   - Anything in the source that has no home in a template section (metadata, rationale, side notes)
     is preserved under Open Questions rather than dropped.
   - Anything a template section needs but the source document does not cover goes under Open
     Questions too, same as author mode — do not invent to fill the gap.

7. **Write** the filled template to `FEATURE_SPEC`: `[name]` from the one-liner or the source
   document's title, `[NNN-slug]` set to `BRANCH`, `[date]` to today, `Status` left as `draft`.

8. **Report**: the created branch, the feature directory, and the spec path. Then point the user at
   `/kaba:clarify` as the next step.

## Key Rules

- **Two modes, one flag.** Default is author-from-one-liner; `--spec <path>` switches to import.
  No other parameter threads through this command.
- **The script owns scaffolding.** Branch and feature-directory creation belong to
  `new-feature.sh` alone.
- **The template is the plugin's, not the project's.** Always resolve it via
  `$(git config kaba.scriptdir)/../templates/spec-template.md`.
- **Never invent.** Every requirement, scenario, edge case, and success criterion must trace to
  something the user said or the imported document stated. Unknowns go to Open Questions — closing
  that list is exactly what `/kaba:clarify` exists to do.
- **Nothing from an imported document is discarded.** If it has no home in the template's sections,
  it goes to Open Questions, not the cutting-room floor.
