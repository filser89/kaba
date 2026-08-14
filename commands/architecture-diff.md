---
description: Fold the just-completed feature's architectural delta into .kaba/architecture.md. Mandatory at the end of every feature.
handoffs:
  - label: Build Specification
    agent: kaba:specify
    prompt: The architecture doc is up to date. Start the next feature specification. I want to build...
---

## User Input

```text
$ARGUMENTS
```

Consider the user input before proceeding (if not empty) — it may supply an explicit base ref to diff against.

## Purpose

Update `.kaba/architecture.md` with the architectural delta this feature introduced — adding, replacing, or deleting pattern entries. Most features change nothing; the common, correct outcome is "no architectural changes."

## Outline

1. **Resolve paths**: repo root via `git rev-parse --show-toplevel`. Run `$(git config kaba.scriptdir)/resolve-feature.sh` to get `FEATURE_DIR` (one of three `KEY=value` lines it prints — `REPO_ROOT`, `FEATURE_DIR`, `FEATURE_SPEC`; read them line-by-line, never `eval`, since a path may contain spaces); the feature plan is `FEATURE_DIR/code-plan.md`. The doc is `<repo_root>/.kaba/architecture.md`; the template and method file are under `$(git config kaba.scriptdir)/../templates/`.
2. **Read and apply the authoring method**: `$(git config kaba.scriptdir)/../templates/architecture-method.md` is the authoritative ruleset for this command — follow its significance decision and definitions exactly. Also read the template, the existing `architecture.md`, and `FEATURE_DIR/code-plan.md` if it exists (interpretive context — see step 6).
3. **Empty/skeleton-doc fallback**: if `architecture.md` is absent or still just the template skeleton (no populated Layers/Patterns/Dependencies), run `/kaba:architecture` instead and stop.
4. **Determine the diff anchor**, in order: (a) an explicit base ref from user input; (b) the commit hash recorded in the doc's `Last updated` line; (c) neither available → STOP and ask the human for a base ref. Never guess an anchor and never fall back to a branch comparison — on a trunk-based workflow a branch merge-base equals HEAD and produces an empty footprint.
5. **Compute the footprint** relative to the anchor, including uncommitted and untracked:
   - `git diff --name-status --find-renames <anchor>` (committed since the anchor + staged + unstaged), plus
   - `git ls-files --others --exclude-standard` (untracked new files).
   - Exclude paths under `spec/`, `test/`, `docs/`, `.kaba/`. This footprint + the code it points at is the authoritative reality.
6. **Significance gate** (method file): pass only pattern-level changes. When a represented layer is touched, regenerate its entry from the layer's whole current state (re-read its files), not the diffed file alone, so the prevailing shape is judged correctly. Read `code-plan.md` as interpretive context and a cross-check of the feature's intent, but the code wins on any conflict.
7. **Apply the merge rule, per affected unit**: add a new entry, replace a changed entry (regenerated wholesale from current reality), or delete a removed entry. Untouched entries stay byte-for-byte. Update the Directory Structure for added/removed dirs. Set the `Last updated` line to today's date, `/kaba:architecture-diff after <feature>`, and `commit <short-hash>` from `git rev-parse --short HEAD` — this is the next run's diff anchor.
8. **Report**: a changelog (added / replaced / deleted), or "no architectural changes — feature conforms to existing patterns."

## Report Format

Either a changelog —
- Added: [entries] · Replaced: [entries] · Deleted: [entries] · Directory Structure: [updates]

— or, when nothing passes the significance gate:

"No architectural changes — feature conforms to existing patterns."

## Key Rules

- **Patterns, not inventory; current state, not history** — per the method file. Replace/delete; never append history.
- **Idempotent**: regenerate the candidate entry and write only if a documented field differs. Same state in → zero edits.
- **Reality wins**: the diff + code are authoritative; `code-plan.md` only interprets.
- **Apply the method file** for the significance decision and all definitions; do not override its rules.
