---
name: architecture
description: Full codebase scan that creates or rebuilds the project architecture document at .kaba/architecture.md. Human-triggered (project setup, or when the doc is suspected stale).
handoffs:
  - label: Build Specification
    agent: kaba:specify
    prompt: Now that the architecture is documented, build the next feature specification. I want to build...
---

## User Input

```text
$ARGUMENTS
```

Consider the user input before proceeding (if not empty) — it may name a focus area or supply the integration branch to record.

## Purpose

Produce `.kaba/architecture.md` from a full scan of the codebase: a current-state description of the project's patterns (layers, key patterns, dependencies) that later planning commands trust. This command DELETES the existing doc first and rebuilds it from scratch — it is the full rebuild, never an edit of what is already there.

## Outline

1. **Resolve paths**: repo root via `git rev-parse --show-toplevel`. The doc path is `<repo_root>/.kaba/architecture.md`; the template is `$(git config kaba.scriptdir)/../templates/architecture-template.md`.
2. **Delete the existing doc FIRST**: run `rm -f <repo_root>/.kaba/architecture.md` before any scanning or reading of the codebase. If the file did not exist, continue silently. Do not read, quote, or carry over any of its content — the scan starts from a blank page so the rebuild cannot anchor on stale claims. (The file is tracked in git, so the prior version stays recoverable via `git show`.)
3. **Read and apply the authoring method**: `$(git config kaba.scriptdir)/../templates/architecture-method.md` is the authoritative ruleset for this command — follow its definitions, the significance decision, and the integration-branch chain exactly. Also read the template (the output structure) and the project rules (CLAUDE.md/AGENTS.md, per `.kaba/config.yml`'s `rules_files`) for declared conventions/stack.
4. **Determine the integration branch** using the method file's detection chain (or the value in user input), and record it in the doc's `Integration branch` metadata line.
5. **Dependencies**: read the dependency manifest(s) present (Gemfile / package.json / pyproject.toml / go.mod / …) → fill Dependencies with libraries that own an architectural concern.
6. **Directory Structure**: build the annotated tree from the real source tree, applying the method file's inclusion test.
7. **Layers**: apply the method file's Layer definition to every source directory → one entry per layer (the prevailing shape per layer).
8. **Key Patterns**: trace a representative end-to-end flow → the established Key Patterns (method file's definition).
9. **Known Inconsistencies**: where a concern is implemented multiple conflicting ways, record the canonical pattern (declared in the project rules, else dominant) in its normal section AND list material divergences under `## Known Inconsistencies` ("do not emulate — refactor candidates"). Do not fabricate one clean pattern. Remove the section if the codebase is consistent.
10. **Greenfield guard**: if there is essentially no application code (only framework-generated scaffolding/base files; no project-authored application code), the doc is the metadata header + Overview + Directory Structure ONLY — delete the Layers, Key Patterns, Dependencies, and Known Inconsistencies sections entirely.
   - The Overview is **at most 4 sentences** and may state ONLY: (a) the stack, (b) that the project is freshly scaffolded with no application architecture yet, (c) that Layers/Key Patterns/Dependencies are omitted until application code exists.
   - It **MUST NOT** name or summarize any test file or the test suite, and **MUST NOT** describe any flow, behavior, interface, or capability that is not already implemented in the application code. Those are "what should be" — they belong to spec.md, never this doc.
   - The test directory may appear in the Directory Structure with a single generic annotation only; do not annotate it with what the tests cover.
11. **Write**: fill the template and write a fresh `<repo_root>/.kaba/architecture.md` (the file was deleted in step 2, so this creates it anew). Set the `Last updated` line to today's date, `/kaba:architecture`, and `commit <short-hash>` from `git rev-parse --short HEAD` (the anchor for subsequent diff runs).
12. **Report**: summarize what was found (counts of layers, key patterns, dependencies; inconsistencies flagged; greenfield if applicable).

## Report Format

- Integration branch: [branch]
- Layers: [N] · Key Patterns: [N] · Dependencies: [N] · Known Inconsistencies: [N or none]
- Greenfield: [yes/no]
- Written to `.kaba/architecture.md`

## Key Rules

- **Delete before scanning** — the old doc is removed in step 2 and never consulted. A rebuild that reuses the previous text is not a rebuild; every claim in the new doc must come from this run's read of the codebase.
- **Describe what IS**, not what should be (that is the project rules) and not history.
- **Patterns, not inventory** — one entry per layer, not per file.
- **Canonical examples and pattern files are real paths**, never inlined snippets.
- **Apply the method file** for every definition and judgment; do not re-derive or override its rules here.
