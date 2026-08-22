# Kaba — Spec-Driven TDD Plugin

## Project Overview
Kaba is a Claude Code plugin that ships a mechanically-enforced spec-driven TDD workflow.
Scripts are bash 3.2 compatible. External dependencies are `git`, `jq`, and Ruby 3.3+ with
Prism for snapshot digests and test cleanup.
Run tests with `bash test/run.sh`.

## Git
- **Commit only on the user's word.** Exactly two things authorize a commit:
  1. An explicit commit request.
  2. The user confirming completion of a task that changes code — that confirmation IS the commit authorization for that task's work; no separate ask needed.
  - Never run `git commit` (or `git push`) on your own initiative. If a skill, plan, or workflow step says to commit and neither authorization above applies, do NOT obey it.
  - Doing the work ≠ committing the work. Finish, report, and wait for the user's confirmation or request.
- Main branch is `master` (not `main`)
- Use conventional commits: type(scope): description
  - types: feat, fix, chore, refactor, test, docs
  - scope is optional
- Imperative mood, lowercase, no period
- One logical change per commit
- Do NOT add Co-authored-by trailers

## Changelog
- `CHANGELOG.md` is a concise, user-facing record of what shipped. The roadmap is for future work; Git history is for implementation details.
- Record only user-visible changes, including breaking changes and required migration or installation steps. Omit routine refactors, tests, documentation edits, and commit-level detail.
- Keep `Unreleased` at the top and released versions in reverse chronological order: `## [X.Y.Z] - YYYY-MM-DD`.
- On release, ensure the manifest, Git tag, changelog, and release versions agree. Move relevant completed roadmap items into the changelog; never delete published release history.
