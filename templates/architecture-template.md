# Architecture: [PROJECT NAME]

**Last updated**: [DATE] — by [/kaba:architecture (full scan) | /kaba:architecture-diff after FEATURE]
**Integration branch**: [branch the per-feature delta diffs against, e.g. main]

**Note**: This document describes the CURRENT structure of the codebase — what is, not
what was or why. Principles and conventions live in the project rules; this file
describes how the code is actually organized right now. When a feature changes
a pattern, REPLACE the affected section — do not append history. This document is
maintained by `/kaba:architecture` (full scan) and `/kaba:architecture-diff`
(per-feature delta).

## Overview

<!--
  ACTION REQUIRED: One paragraph. What kind of project is this, what are its primary
  entry points, and what is the dominant request/data flow. Describe what IS — no
  history, no rationale.
-->

[One paragraph: project kind, primary entry points, dominant request/data flow.]

## Directory Structure

<!--
  ACTION REQUIRED: An annotated tree of the architecturally-meaningful directories,
  each annotated with what lives there. Keep a directory if this project wrote or
  arranged its contents — a layer lives there, or it holds app-specific code/config
  an agent must find — INCLUDING framework-conventional dirs (e.g. app/models,
  app/controllers) and architectural config (e.g. config/routes.rb). Omit only pure
  framework plumbing with no navigational value (bin/, tmp/, log/, vendor/, generated
  config, node_modules/). The axis is "wrote/arranged it" vs "framework plumbing" —
  not "did the framework create the folder."
-->

```
[root]/
├── [dir]/    # [what lives here]
├── [dir]/    # [what lives here]
└── [dir]/    # [what lives here]
```

## Layers

<!--
  ACTION REQUIRED: One entry per architectural layer the codebase ACTUALLY uses. Layer
  names are stack-specific — use whatever this stack calls them (e.g. models /
  controllers / services; or contexts; or ports / adapters). Do NOT invent layers the
  code does not have. Add layers as the project grows — a young project may have only
  one or two. Repeat the entry block below for each layer.

  Example of a filled-in entry (ILLUSTRATIVE ONLY — your layer names, paths, and
  conventions come from the real codebase, not from this example):

    ### Services
    - **Location**: app/services/
    - **Naming**: VerbNoun (e.g. CreateBookmark)
    - **Base class / interface**: ApplicationService
    - **Responsibilities**: orchestrate multi-step writes; the only place that calls
      external APIs; invoked from controllers as `CreateBookmark.new(...).call`
    - **Canonical example**: app/services/create_bookmark.rb
-->

### [Layer name]

- **Location**: [directory path]
- **Naming**: [naming convention]
- **Base class / interface**: [shared base class, module, protocol, or "none"]
- **Responsibilities**: [what lives here in THIS codebase and how it is invoked — the
  line that tells the next agent which layer a new piece of logic belongs in]
- **Canonical example**: [path to one real file that exemplifies the layer]

<!-- Repeat the entry above for each layer. -->

## Key Patterns

<!--
  ACTION REQUIRED: Recurring patterns that cross layers and are not captured by a single
  layer entry — e.g. how authentication works end-to-end, how errors become responses,
  how pagination works. Point to the real files; do NOT inline code. Repeat the entry
  block for each pattern.
  [REMOVE THIS SECTION IF THERE ARE NO CROSS-CUTTING PATTERNS YET]
-->

### [Pattern name]

- **What it does**: [one line]
- **How it works**: [the mechanism end-to-end — concrete flow]
- **Files**: [the real files that implement it]

<!-- Repeat the entry above for each pattern. -->

## Dependencies

<!--
  ACTION REQUIRED: External libraries that OWN an architectural concern — not every
  package, only the ones that shape how code is written (e.g. a serializer library, an
  auth library). One row each. Keep concrete library names out of placeholders; fill
  the table from the real codebase.
  [REMOVE THIS SECTION IF NO EXTERNAL LIBRARY OWNS AN ARCHITECTURAL CONCERN YET]
-->

| Concern | Library | Notes |
|---|---|---|
| [concern] | [library] | [how/where used] |

## Known Inconsistencies

<!--
  ACTION REQUIRED: Only when a concern is implemented multiple conflicting ways. List
  each material divergence from the canonical pattern recorded above, with the files,
  marked "do not emulate — refactor candidate". Populated by the full scan, which can
  see the whole codebase.
  [REMOVE THIS SECTION ENTIRELY IF THE CODEBASE IS CONSISTENT]
-->

### [Concern]

- **Canonical pattern**: [the pattern recorded above that code should follow]
- **Divergences**: [files that diverge] — do not emulate; refactor candidates
