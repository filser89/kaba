# Changelog

## [Unreleased]

### Added

- Added installable Codex packaging, explicit-only skill metadata, and Codex `apply_patch` enforcement while keeping the existing Claude package and marketplace.

### Changed

- Preserved `review-tests` conversation isolation in Codex by delegating to a fresh-context reviewer when native forked skill execution is unavailable.
- Made SessionStart rewiring resolve Codex's `cwd` payload and the active installed plugin path.

## [0.3.0] - 2026-08-22

### Added

- Added allowlist schema v3 with explicit MODIFY, REMOVE, PIN, and TOUCH actions.
- Added AST-based snapshot checks that detect status-preserving test edits.

### Changed

- Moved plugin commands to skills while preserving the existing `/kaba:<name>` interface.
- Isolated `review-tests` in a forked context so it reviews without the implementer's conversation history.
- Documented the runtime requirements: `git`, scoped use of `jq`, and Ruby 3.3+ with Prism for snapshot capture and test cleanup.

### Breaking

- Test plans now use schema v3 and snapshots use version 2. Active sessions using older formats must finish with the previous Kaba version or restart their test session.
