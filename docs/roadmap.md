# Kaba Roadmap

Kaba supports Claude Code and has an installable Codex compatibility implementation. This roadmap
contains only future work; completed user-visible changes are recorded in `CHANGELOG.md`, and the
Codex mechanism-spike evidence is recorded in `docs/codex-compatibility-spike.md`.
Active Codex failures, fixes, and release evidence are tracked in
`docs/codex-release-readiness.md`.

## Codex release validation

The mechanism spike proved that one flat, self-contained plugin root works for both hosts. Before
declaring Codex support production-ready:

1. Exercise the remaining Kaba skills explicitly in Codex, including arguments, prior-run
   confirmation, and next-step guidance. Packaging discovery covered all thirteen skills; the
   behavioral spike covered `review-tests` and its scoped argument mode.
2. Run one complete greenfield feature through both Claude Code and Codex and observe every git,
   session-lock, snapshot, cleanup, and end gate firing in the intended order.
3. Verify the hook-trust onboarding in the released Codex UI and document any product-specific
   trust reset behavior after plugin updates.
4. Recheck non-`apply_patch` edit surfaces as Codex evolves. The git pre-commit and end gates remain
   the guarantee when an edit path cannot be inspected before the tool runs.

Do not introduce adapter packages or generated `dist/` trees unless a future host incompatibility
cannot be expressed in the shared manifest, skill metadata, hook, or script layer.

## Additional stack support

A second real stack consumer—not a target version—will determine the stack-adapter boundary.
Keep that decision separate from harness compatibility: Codex support must not force a speculative
test-framework abstraction, and a future non-RSpec stack must not require duplicating harness
packaging.
