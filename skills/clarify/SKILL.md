---
name: clarify
description: Identify underspecified areas and unconfirmed assumptions in the current feature
  spec by asking up to 5 highly targeted clarification questions, then encode every answer back
  into spec.md.
handoffs:
  - label: Acceptance Criteria
    agent: kaba:acceptance-criteria
    prompt: Decompose the clarified spec's acceptance scenarios into test-oriented acceptance criteria
    send: true
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Purpose

Detect and reduce ambiguity, missing decision points, and unconfirmed assumptions in the active
feature specification, and record every resolution directly in the spec file.

This covers two related gaps, treated the same way once found: an area the spec never addresses at
all, and a decision the spec states as settled fact without the user ever having confirmed it.
`/kaba:specify` pushes what it cannot settle to Open Questions, but a decision can still read as
fact elsewhere in the spec — a requirement, a scenario, a success criterion — without anyone having
actually confirmed it. Both kinds get surfaced, confirmed or corrected, and written back to the
spec; neither is ever left looking settled while still materially unconfirmed.

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

   **Unconfirmed decisions cap the category they touch.** A decision is unconfirmed when it is
   either (a) still sitting in `## Open Questions` — `/kaba:specify` puts there anything it could
   not settle, so every entry there is by definition unconfirmed — or (b) stated as settled fact
   somewhere else in the spec (a requirement, scenario, edge case, or success-criterion bullet)
   without a trailing `(user-confirmed YYYY-MM-DD)` marker and without an existing
   `## Clarifications` Q&A bullet already covering the same decision. An unconfirmed decision caps
   the category it touches at **Partial** — never mark a category Clear on the strength of an
   unconfirmed decision alone.

   For each category with Partial or Missing status, add a candidate question opportunity unless:
   - Clarification would not materially change implementation or validation strategy
   - Information is better deferred to planning phase (note internally)

   Every entry still in Open Questions is automatically a candidate, subject to these same
   exclusion filters — a genuinely trivial one does not have to spend a question, but starts from a
   presumption of materiality since the spec author flagged it as unresolved rather than guessed.

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
       - When the question derives from a decision stated as fact **elsewhere in the spec** (a
         requirement, scenario, edge case, or success-criterion bullet — never an Open Questions
         entry, which by definition states no position) that lacks a `(user-confirmed YYYY-MM-DD)`
         marker, format the recommendation instead as: `**Recommended:** Option [X] — current spec
         states: <one-line restatement>. <1–2 sentences why it is reasonable>.` The remaining
         options are the plausible alternative interpretations a different reasonable reader might
         have expected. Never present such a question without a recommendation — the user must be
         able to confirm with a single "yes".
       - When the question derives from an entry still in Open Questions, there is no stated
         position to restate — use the plain default format above
         (`**Recommended:** Option [X] - <reasoning>`), recommending from best practices and
         context like any other candidate question.
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
    - If no valid questions exist at start, **stop and ask before doing anything else**: the spec has
      no open questions and no unconfirmed decisions left, so a re-run has nothing to clarify and
      would only re-derive settled answers, rewriting `spec.md` in the process. Say that, and ask
      whether to proceed anyway (e.g. the user knows of an ambiguity the scan did not surface). Ask,
      then **end your turn** — do not answer yourself. Use `AskUserQuestion` if it is available.
      Continue only on an explicit yes. This is clarify's own version of the prior-run gate the other
      artifact-producing commands run as a script step; clarify deliberately does **not** gate on its
      output existing, because re-running to resolve something still unclear is exactly what this
      command is for.

6. Integration after EACH accepted answer (incremental update approach):
    - Maintain in-memory representation of the spec (loaded once at start) plus the raw file contents.
    - For the first integrated answer in this session:
       - Ensure a `## Clarifications` section exists (create it just after the highest-level contextual/overview section per the spec template if missing).
       - Under it, create (if not present) a `### Session YYYY-MM-DD` subheading for today.
    - Append a bullet line immediately after acceptance: `- Q: <question> → A: <final answer>`.
    - Then immediately apply the clarification:
       - **If it resolves an entry in Open Questions**: remove that entry from Open Questions and
         write the answer into the most appropriate section(s) below — this is how the Open
         Questions list is worked toward empty.
       - **If it confirms a decision already stated as fact elsewhere in the spec, as-is**: append
         `(user-confirmed YYYY-MM-DD)` immediately after that bullet/requirement/scenario. No other
         spec text changes.
       - **If it overrides that decision**: rewrite the bullet/requirement/scenario in place to
         state the chosen answer, with the `(user-confirmed YYYY-MM-DD)` marker, then update every
         requirement, scenario, or section derived from the old decision per the mapping below —
         leave no contradictory text behind.
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
       - Terminology conflict → Normalize term across spec; retain original only if necessary by adding `(formerly referred to as "X")` once.
    - If the clarification invalidates an earlier ambiguous statement, replace that statement instead of duplicating; leave no obsolete contradictory text.
    - Save the spec file AFTER each integration to minimize risk of context loss (atomic overwrite).
    - Preserve formatting: do not reorder unrelated sections; keep heading hierarchy intact.
    - Keep each inserted clarification minimal and testable (avoid narrative drift).

7. Validation (performed after EACH write plus final pass):
   - Clarifications session contains exactly one bullet per accepted answer (no duplicates).
   - Total asked (accepted) questions ≤ 5.
   - Updated sections contain no lingering vague placeholders the new answer was meant to resolve.
   - No contradictory earlier statement remains (scan for now-invalid alternative choices removed).
   - Markdown structure valid; only allowed new headings: `## Clarifications`, `### Session YYYY-MM-DD`.
   - Terminology consistency: same canonical term used across all updated sections.
   - Every unconfirmed decision resolved this session now carries either a
     `(user-confirmed YYYY-MM-DD)` marker at its original location, or has been removed from Open
     Questions and integrated per step 6 — never left ambiguous.

8. Write the updated spec back to `FEATURE_SPEC`.

Context for prioritization: $ARGUMENTS

## Completion Report

Report completion (after questioning loop ends or early termination):
- Number of questions asked & answered.
- Path to updated spec.
- Sections touched (list names).
- `Assumptions: <N> confirmed, <M> overridden, <K> still unconfirmed` — listing the unconfirmed
  ones (decisions that stayed in Open Questions or kept no `(user-confirmed YYYY-MM-DD)` marker
  because the question quota was reached first).
- Coverage summary table listing each taxonomy category with Status: Resolved (was Partial/Missing and addressed), Deferred (exceeds question quota or better suited for planning), Clear (already sufficient), Outstanding (still Partial/Missing but low impact). A category resting on an unconfirmed decision is never Clear — it appears as Deferred or Outstanding.
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
- **Every entry in Open Questions is unconfirmed by definition**, and so is any decision stated as
  fact elsewhere in the spec without a `(user-confirmed YYYY-MM-DD)` marker or a matching
  `## Clarifications` bullet — never mark either kind settled without one.
- **Confirmed vs. overridden are different writes.** Confirming as-is only adds the marker;
  overriding rewrites the statement and cascades to everything derived from it. Never blend the two.
