# Architecture Doc — Authoring Method

**This is NOT a template to fill in.** It is a static ruleset that `/kaba:architecture` and `/kaba:architecture-diff` read and APPLY at runtime — the authoritative definitions and decisions those commands MUST follow. Its headings are rules, not fields to populate, and nothing here is edited per run. It defines what goes in `.kaba/architecture.md` and how to decide it; the commands own their own procedures, this file owns the *rules*.

## Governing principles

1. **Patterns, not inventory.** The doc describes patterns — layers, shared cross-cutting mechanisms, dependencies, and conventions code must follow to stay consistent. A change earns a doc edit **only if it introduces, changes, or removes a pattern.** Adding/removing an *instance* of an existing pattern, or a feature that merely *uses* existing patterns, produces **no doc change.** The steady state is that most features change the doc nothing.
2. **Current state, never history.** Every section describes how things are *now*. Replace or delete affected entries — never append "previously X, now Y" notes or changelogs. The only temporal element in the file is the single `Last updated` line.

## Inference definitions

- **Layer** — a directory (or coherent group) of same-role files sharing a naming + base-class/interface pattern. Document it by sampling representative files to infer **Naming** and **Base class / interface**, picking a **Canonical example** (simplest complete representative), and writing **Responsibilities** from what the files do + how they're invoked (trace call sites). An entry describes the **prevailing** shape across the layer's files as they currently exist — never one file's intent.
- **Key Pattern** — a reusable cross-cutting mechanism other features must follow/reuse to stay consistent (auth, error→response, pagination, the request lifecycle, job dispatch). Documented once, when first established. Test: *must a future feature conform to this?* "Crosses layers" is NOT the test (simple CRUD crosses layers but is the same lifecycle every feature reuses — documented once); "must be reused for consistency" is.
- **Dependency** — an external library that owns an architectural concern (serializer lib, auth lib), from the manifest. Not every package.
- **Directory Structure inclusion test** — keep a directory if it houses code this project wrote or arranged (a layer lives there, or app-specific code/config an agent must find), *including* framework-conventional dirs like `app/models`, `app/controllers`, and architectural config like `config/routes.rb`. Omit only pure framework plumbing with no navigational value (`bin/`, `tmp/`, `log/`, `vendor/`, `config/boot.rb`, generated assets, `node_modules/`). Axis: "wrote/arranged it" vs "framework plumbing" — not "did the framework create the folder."

## Significance decision

When a feature introduces something, decide whether it changes the *set of patterns*:

1. **Structurally new** (a dir/role/dependency that fits no existing layer) → observable fact → **record** (new layer / dependency / Key Pattern if it's a reusable mechanism).
2. **A changed *shape* within an existing layer** (different base class, return convention, naming) → **consult the project rules (CLAUDE.md/AGENTS.md, per `.kaba/config.yml`'s `rules_files`): is this a declared rule/convention?** Declared → record/update the pattern. Not declared → treat as an instance/outlier → no doc change (optionally flag under Known Inconsistencies if it contradicts a declared rule).
3. **Instance of an existing pattern**, or a feature that only *uses* existing patterns → **no doc change.**

Do not read intent or count occurrences. Convention status is decided by what humans **declared** in the project rules. Caveat: this leans on the discipline that new conventions get declared there; an undeclared in-code convention reads as an outlier until a full scan + human review reconciles it.

Sole instance-level edit that still touches the doc: deleting the file that *was* a layer's canonical example → repoint that one field.

## Classification examples

| Change | Architectural? | Doc action |
|---|---|---|
| First service object introduced | yes — new layer | add Services entry |
| 5th service following the existing pattern | no — instance | none |
| New model alongside existing models, same conventions | no — instance | none |
| New `TagsController` following the controller pattern | no — instance | none |
| Add columns/validations to an existing model | no — domain detail | none |
| Bugfix inside a service, no shape change | no | none |
| First time auth is added (Bearer mechanism) | yes — new shared mechanism | add Key Pattern |
| Centralized error handling via a base controller all inherit | yes — changed + new | replace Controllers entry + add Error-Handling pattern |
| Swap hand-rolled JSON for a serializer gem + `serializers/` | yes | add Serializers layer + Dependency row |
| First background job (`app/jobs`, ApplicationJob) | yes — new layer | add Jobs entry (+ dispatch pattern if shared) |
| Move `app/services → app/operations` / rename base class, declared in the project rules | yes — changed convention | replace the layer entry |
| Rename a single file, no declared convention change | no — one-off | none |
| Service adopts a new shape (e.g. Result object) declared as a rule | yes — changed pattern | replace Services entry (Responsibilities) |
| Same shape change, not declared anywhere | no — outlier | none (flag as inconsistency if it contradicts a declared rule) |
| Remove the last service (refactor away) | yes — pattern gone | delete Services entry |
| Remove one of several models | no — instance | none |
| Delete the file that was a layer's canonical example | minor | repoint that one field |
| Add a gem owning a concern (e.g. pundit + `policies/`) | yes | add Dependency + Authorization layer/pattern |
| Add a non-architectural gem (faker, logging tweak) | no | none |
| Any change under `spec/` or `test/` | no — not app source | none — footprint excludes tests |

## Integration-branch detection chain

Used to compute diffs and recorded by the full scan. In order:
(a) `git symbolic-ref --short refs/remotes/origin/HEAD` (strip `origin/`);
(b) `git config --get init.defaultBranch`;
(c) probe for an existing local branch among `main` / `master` / `trunk`;
(d) if still undetermined → stop and ask the human for the base ref.
