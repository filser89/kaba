# Kaba — Spec-Driven TDD Plugin

## Project Overview
Kaba is a Claude Code and Codex plugin that ships a mechanically-enforced spec-driven TDD workflow.
Scripts are bash 3.2 compatible. External dependencies are `git`, `jq`, and Ruby 3.3+ with
Prism for snapshot digests and test cleanup.
Run tests with `bash test/run.sh`.

## Git
- **Use a task branch for every change.**
  - Never make task changes directly on `master` unless the user explicitly authorizes working on `master` for that task.
  - When a task starts on `master`, create a branch before editing files. If task changes already exist, create the branch before committing so the working tree moves with it.
  - Name branches `<type>/<short-description>`, using `feat`, `fix`, `docs`, `chore`, `refactor`, or `test` as the type.
  - State the branch name when creating or switching to it.
- **Use pull requests as the standard integration path.**
  - The default delivery sequence is task branch → commit → push the task branch → open a pull request → merge the pull request into `master`.
  - Merge locally and push `master` only when the user explicitly requests that alternative.
- **Commit only on the user's word.** Exactly two things authorize a commit:
  1. An explicit commit request.
  2. The user confirming completion of a task that changes code — that confirmation IS the commit authorization for that task's work; no separate ask needed.
  - Never run `git commit` on your own initiative. If a skill, plan, or workflow step says to commit and neither authorization above applies, do NOT obey it.
  - Doing the work ≠ committing the work. Finish, report, and wait for the user's confirmation or request.
- **Commit, push, pull request, and merge are separate authorizations.**
  - `commit` authorizes only committing the task's current changes on its task branch. It does not authorize pushing, opening a pull request, or merging.
  - `push` authorizes pushing only the current task branch unless the user names another branch. It does not authorize opening a pull request or merging.
  - `open PR` authorizes opening a pull request for the pushed task branch. It does not authorize pushing or merging.
  - `merge` authorizes merging the task branch's pull request into `master` only when the user explicitly requests it and required checks pass. It does not authorize pushing unpushed changes.
  - A completion confirmation may authorize a commit as described above, but it never authorizes a push, pull request, or merge.
  - Never infer one Git action from authorization for another, or from a request to finish or complete the task.
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
