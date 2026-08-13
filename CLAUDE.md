# Kaba — Spec-Driven TDD Plugin

## Project Overview
Kaba is a Claude Code plugin that ships a mechanically-enforced spec-driven TDD workflow.
Scripts are bash 3.2 compatible. External dependencies are `git` and `jq` only.
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
