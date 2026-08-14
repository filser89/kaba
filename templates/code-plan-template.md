# Implementation Plan: [FEATURE]

**Feature**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link to spec.md]
**Tests**: [link to the locked test directory / suite this plan satisfies]

**Note**: This template is filled in by the `/kaba:plan-code` command. See `templates/code-plan-template.md` in the kaba plugin for the format reference. All paths, names, and conventions MUST use the project's actual conventions.

## Summary

[What's built + the technical approach, 1–2 lines.]

## Components

<!--
  ACTION REQUIRED: One entry per production component, grouped by layer.
  Map each action/method-level sub-responsibility to the test group it greens.
  Names, responsibilities, and collaboration seams only — NO method bodies, NO logic.

  EXAMPLE:
  ### src/controllers/orders_controller.[ext] (request-handler layer)
  - **Responsibility**: thin request handler for orders; delegates writes to a service
  - **Greens**:
    - `list`   — return the caller's orders, scoped → tests/requests/orders/list (LIST group)
    - `create` — delegate to CreateOrder, return 201 → tests/requests/orders/create (CREATE group)
  - **Collaborators**: calls CreateOrder / UpdateOrder; serializes via OrderSerializer
-->

### [path] ([layer])

- **Responsibility**: [one line]
- **Greens**:
  - `[#action / method / behavior]` — [sub-responsibility] → [test file / describe group it makes green]
- **Collaborators**: [the seams — what it calls and what it returns; or "none"]

<!-- Repeat for each component. Every locked test file MUST be greened by at least one component. -->

## Data Model

<!--
  ACTION REQUIRED: One entry per persisted entity. These are the schema decisions
  the tests cannot see. [REMOVE THIS SECTION IF NO ENTITIES ARE PERSISTED]

  EXAMPLE:
  ### Order
  - **Columns**: total (integer, not null), status (string, not null, default "pending"), customer_id (not null)
  - **Indexes**: customer_id; (customer_id, status)
  - **Constraints / FKs**: customer_id → customers(id)
-->

### [entity]

- **Columns**: [name type — nullability, default]
- **Indexes**: [columns — unique?]
- **Constraints / FKs**: [...]

## Decisions

<!--
  ACTION REQUIRED: One entry per test-invisible decision this command owns.
  Verdict as a directive; reasoning beneath. Use "None — reuses existing patterns" if there are none.

  EXAMPLE:
  ### D1 — response serialization: hand-rolled serializer object (no library)
  - **Constraints**: the response shape required by the request tests; no serializer library in the manifest
  - **Rejected**: a serializer library — a new dependency for a single resource (the trap: reaching for a library before it earns its place)
  - **Flip-point**: adopt a serializer library once 3+ resources need serialization
-->

### D[N] — [decision]: [the verdict, stated as a directive]

- **Constraints**: [the driving facts, grounded in the spec/tests]
- **Rejected**: [alternative] — [why it lost]; [the trap] — [why the plausible default is wrong]
- **Flip-point**: [when this choice would change]

## Architectural Delta

<!--
  ACTION REQUIRED: New patterns/layers/dependencies this feature introduces vs architecture.md.
  Use "None — reuses existing patterns" if pure reuse.

  EXAMPLE:
  Establishes the Models, Request-Handler, and Service layers and the token-auth mechanism
  (all declared in the project's conventions/rules — applied here for the first time, not invented).
-->

[The delta, or "None — reuses existing patterns".]

## Build Order

<!--
  ACTION REQUIRED: Dependency-ordered sequence of the components above — the task list for implement-code.

  EXAMPLE:
  1. schema: create customers + orders
  2. auth-credential model + token authentication → greens tests/requests/authentication
  3. Order model + validations → greens tests/models/order
  4. orders list endpoint + route → greens tests/requests/orders/list
-->

1. [unit] → greens [test file / group]
