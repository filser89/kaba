---
name: clarify
disable-model-invocation: true
description: Identify underspecified areas and unconfirmed assumptions in the current feature
  spec by asking up to 5 highly targeted clarification questions, then encode every answer back
  into spec.md.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Purpose

Detect and reduce ambiguity, missing decision points, and unconfirmed assumptions in the active
feature specification, and record every resolution directly in the spec file.

Scan consequential gaps, conflicting statements, and assumptions that have no support in the
supplied requirements. Explicit supplied requirements are the contract; clarify their ambiguous
meaning or genuine conflicts without reopening them for missing approval metadata. Integrate
answers directly into current-state requirements and keep unanswered choices explicit.

This pass is expected to run — and be completed — before moving on to `/kaba:acceptance-criteria`.
If the user explicitly states they are skipping clarification (e.g., exploratory spike), you may
proceed, but must warn that downstream rework risk increases.

## Outline

1. **Resolve feature paths**: Run `$(git config kaba.scriptdir)/resolve-feature.sh` from the repo
   root **once**. It prints three `KEY=value` lines — `REPO_ROOT`, `FEATURE_DIR`, `FEATURE_SPEC` —
   read them line-by-line (never `eval`; a path may contain spaces). If the script exits non-zero,
   abort and instruct the user to re-run `/kaba:specify` or verify the feature branch environment.
   For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or
   double-quote if possible: "I'm Groot").

2. **IF PRESENT**: Read the project rules (CLAUDE.md/AGENTS.md, per `.kaba/config.yml`'s
   `rules_files`) for project principles and constraints relevant to the scan.

3. Load the spec from `FEATURE_SPEC`. Perform a structured ambiguity, coverage & unconfirmed-decision
   scan using this taxonomy. For each category, mark status: Clear / Partial / Missing. Produce an
   internal coverage map used for prioritization (do not output raw map unless no questions will be
   asked).

   Functional Scope & Behavior:
   - Core user goals & success criteria
   - Explicit out-of-scope declarations
   - User roles / personas differentiation

   Domain & Data Model:
   - Entities, attributes, relationships
   - Identity & uniqueness rules
   - Lifecycle/state transitions
   - Data volume / scale assumptions

   Interaction & UX Flow:
   - Critical user journeys / sequences
   - Error/empty/loading states
   - Accessibility or localization notes

   Non-Functional Quality Attributes:
   - Performance (latency, throughput targets)
   - Scalability (horizontal/vertical, limits)
   - Reliability & availability (uptime, recovery expectations)
   - Observability (logging, metrics, tracing signals)
   - Security & privacy (authN/Z, data protection, threat assumptions)
   - Compliance / regulatory constraints (if any)

   Integration & External Dependencies:
   - External services/APIs and failure modes
   - Data import/export formats
   - Protocol/versioning assumptions

   Edge Cases & Failure Handling:
   - Negative scenarios
   - Rate limiting / throttling
   - Conflict resolution (e.g., concurrent edits)

   Constraints & Tradeoffs:
   - Technical constraints (language, storage, hosting)
   - Explicit tradeoffs or rejected alternatives

   Terminology & Consistency:
   - Canonical glossary terms
   - Avoided synonyms / deprecated terms

   Completion Signals:
   - Acceptance criteria testability
   - Measurable Definition of Done style indicators

   Misc / Placeholders:
   - TODO markers / unresolved decisions
   - Ambiguous adjectives ("robust", "intuitive") lacking quantification

   **Source fidelity**: Treat explicit supplied requirements as settled unless they conflict or
   leave a consequential choice unresolved. A missing confirmation marker is not an ambiguity.
   Preserve the source's specificity and limitations. Separate known Delivery Obligations from
   unresolved questions; runtime configuration behavior, security, deadlines, and user-visible
   setup remain behavioral requirements. Partial/Missing categories are prompts for inspection,
   not permission to invent policy or require irrelevant functionality.

4. Generate (internally) a prioritized queue of candidate clarification questions (maximum 5). Do
   NOT output them all at once. Apply these constraints:
    - Maximum of 5 total questions across the whole session.
    - Each question must be answerable with EITHER:
       - A short multiple‑choice selection (2–5 distinct, mutually exclusive options), OR
       - A one-word / short‑phrase answer (explicitly constrain: "Answer in <=5 words").
    - Only include questions whose answers materially impact architecture, data modeling, task
      decomposition, test design, UX behavior, operational readiness, or compliance validation.
    - Ensure category coverage balance: attempt to cover the highest impact unresolved categories
      first; avoid asking two low-impact questions when a single high-impact area (e.g., security
      posture) is unresolved.
    - Exclude questions already answered, trivial stylistic preferences, or plan-level execution
      details (unless blocking correctness).
    - Favor clarifications that reduce downstream rework risk or prevent misaligned acceptance
      tests.
    - If more than 5 categories remain unresolved, select the top 5 by (Impact * Uncertainty)
      heuristic. Within this heuristic, weight impact highest for unconfirmed decisions about: data
      lifecycle (deletion, cascade vs. preserve, retention), relationship cardinality (one-to-one
      vs. one-to-many vs. many-to-many), security/privacy posture, and anything irreversible or
      destructive. Convenience defaults (formats, naming, cosmetic behavior) rank low and are
      usually excluded by the materiality filter.

5. Sequential questioning loop (interactive):
    - Present EXACTLY ONE question at a time.
    - For multiple‑choice questions:
       - **Analyze all options** and determine the **most suitable option** based on:
          - Best practices for the project type
          - Common patterns in similar implementations
          - Risk reduction (security, performance, maintainability)
          - Alignment with any explicit project goals or constraints visible in the spec
       - Present your **recommended option prominently** at the top with clear reasoning (1-2
         sentences explaining why this is the best choice).
       - Format as: `**Recommended:** Option [X] - <reasoning>`
       - If the spec states a position whose meaning is genuinely ambiguous, quote that
         position and explain the consequential interpretations. Preserve supplied requirements
         unless the human explicitly revises them.
       - Then render all options as a Markdown table:

       | Option | Description |
       |--------|-------------|
       | A | <Option A description> |
       | B | <Option B description> |
       | C | <Option C description> (add D/E as needed up to 5) |
       | Short | Provide a different short answer (<=5 words) (Include only if free-form alternative is appropriate) |

       - After the table, add: `You can reply with the option letter (e.g., "A"), accept the recommendation by saying "yes" or "recommended", or provide your own short answer.`
    - For short‑answer style (no meaningful discrete options):
       - Provide your **suggested answer** based on best practices and context.
       - Format as: `**Suggested:** <your proposed answer> - <brief reasoning>`
       - Then output: `Format: Short answer (<=5 words). You can accept the suggestion by saying "yes" or "suggested", or provide your own answer.`
    - After the user answers:
       - If the user replies with "yes", "recommended", or "suggested", use your previously stated recommendation/suggestion as the answer.
       - Otherwise, validate the answer maps to one option or fits the <=5 word constraint.
       - If ambiguous, ask for a quick disambiguation (count still belongs to same question; do not advance).
       - Once satisfactory, record it in working memory (do not yet write to disk) and move to the next queued question.
    - Stop asking further questions when:
       - All critical ambiguities resolved early (remaining queued items become unnecessary), OR
       - User signals completion ("done", "good", "no more"), OR
       - You reach 5 asked questions.
    - Never reveal future queued questions in advance.
    - If source coverage is complete and no consequential questions remain, report zero questions,
      give a compact coverage summary, and state that the spec is ready for `/kaba:acceptance-criteria`.
      Leave `spec.md` unchanged; no invented question or redundant approval is needed.
    - If no valid question can be asked but consequential unknowns remain (for example, the human
      deferred them), preserve and report them explicitly. Let the human choose whether to resolve
      them or proceed with the stated gaps; do not claim full coverage or invent answers.

6. Integration after EACH accepted answer (incremental update approach):
    - Maintain in-memory representation of the spec (loaded once at start) plus the raw file contents.
    - Apply each answer directly to the relevant current-state section:
       - Remove the resolved Open Questions entry and state its answer in the appropriate section.
       - Rewrite any contradictory or derived text so the spec has one consistent requirement.
       - Known documentation/configuration example/CI/setup/completion tasks → Delivery Obligations,
         with a stable DO-NNN ID, source reference, and completion check.
       - Functional ambiguity → Update or add a bullet in Functional Requirements.
       - User interaction / journey distinction → Update the relevant Acceptance Scenarios entry
         with the clarified actor, constraint, or step.
       - Data shape / entities → Update the Functional Requirements (or the Acceptance Scenarios
         bullet where the data appears) with the clarified fields, types, or relationships,
         preserving ordering; note added constraints succinctly.
       - Non-functional constraint → Add/modify measurable criteria in Success Criteria (convert
         vague adjective to metric or explicit target).
       - Edge case / negative flow → Add a new bullet under Edge Cases.
       - Scope boundary → Add or update the explicit exclusion in Out of Scope.
       - Terminology conflict → Normalize the canonical term across the spec while preserving source meaning.
    - If the clarification invalidates an earlier ambiguous statement, replace that statement instead of duplicating; leave no obsolete contradictory text.
    - Save the spec file AFTER each integration to minimize risk of context loss (atomic overwrite).
    - Preserve formatting: do not reorder unrelated sections; keep heading hierarchy intact.
    - Keep each inserted clarification minimal and testable (avoid narrative drift).

7. Validation (performed after EACH write plus final pass):
   - Every accepted answer is reflected in current requirements or Delivery Obligations; no answer log or dated confirmation markers are added.
   - Total asked (accepted) questions ≤ 5.
   - Updated sections contain no lingering vague placeholders the new answer was meant to resolve.
   - No contradictory earlier statement remains (scan for now-invalid alternative choices removed).
   - Markdown structure and template sections remain valid.
   - Terminology consistency: same canonical term used across all updated sections.
   - Supplied requirements and source references remain intact except for explicit revisions.
   - Remaining consequential unknowns stay in Open Questions; known delivery tasks do not.

8. Write the updated spec back to `FEATURE_SPEC` only if answers were integrated.

Context for prioritization: $ARGUMENTS

## Completion Report

Report completion (after questioning loop ends or early termination):
- Number of questions asked & answered.
- Path to updated spec.
- Sections touched (list names).
- Remaining consequential questions and their effects on planning.
- Compact coverage summary: Clear, Resolved, Deferred, or Outstanding, based on the actual
  supplied contract and unanswered choices.
- If any Outstanding or Deferred remain, recommend whether to proceed to `/kaba:acceptance-criteria` or run `/kaba:clarify` again later.
- Suggested next command.

## Key Rules

- If no meaningful ambiguities found (or all potential questions would be low-impact), respond: "No critical ambiguities detected worth formal clarification." and suggest proceeding.
- If spec file missing, instruct user to run `/kaba:specify` first (do not create a new spec here).
- Never exceed 5 total asked questions (clarification retries for a single question do not count as new questions).
- Avoid speculative tech stack questions unless the absence blocks functional clarity.
- Respect user early termination signals ("stop", "done", "proceed").
- If no questions asked due to full coverage, output a compact coverage summary (all categories Clear) then suggest advancing.
- If quota reached with unresolved high-impact categories remaining, explicitly flag them under Deferred with rationale.
- **Preserve supplied requirements.** Ask about consequential ambiguity or conflict, not missing
  approval provenance. Integrate answers as current-state prose without conversation history.
- **Keep delivery distinct.** Known deliverables belong in Delivery Obligations with completion
  checks; behavioral requirements remain testable and unresolved choices remain explicit.

## Next Step

When the Open Questions list is empty and every answer is encoded in `spec.md`, the next step is
`/kaba:acceptance-criteria`, which decomposes the clarified acceptance scenarios into
test-oriented criteria. If Outstanding or Deferred items remain, name them and let the user choose
between proceeding and another `/kaba:clarify` pass later — see **Completion Report**.
