# kaba

kaba is a Claude Code and Codex plugin that ships a **mechanically-enforced spec-driven TDD
workflow** — not a prompt pack. The two-session split (tests first, implementation second) and
the boundary between them are held by git hooks and pass/fail scripts, not by asking the agent
nicely. See [docs/workflow.md](docs/workflow.md) for the full pipeline and the reasoning behind it.

Kaba supports Rails/RSpec and standard Go testing. Runner adapters discover test
identities, execute complete uncached captures, compute structural source digests,
and perform source-aware cleanup. See [runner contracts](docs/test-runners.md) for
supported Go source forms and command limits.

## Install

**Dependencies:**

- `git` ≥ 2.28 — required by the workflow and its enforcement gates.
- `jq` — required by runner/snapshot/cleanup operations and ownership reporting.
  `scripts/snapshot-tests.sh` and `scripts/cleanup-tests.sh` require it;
  `scripts/banned-patterns.sh` needs it for JSON or explicit-runner inventory inspection;
  and the real-time `scripts/session-lock-guard.sh` deliberately fails open without it while the
  git pre-commit boundary remains active. Install `jq` to retain the complete enforcement and
  reporting path.
- `ruby` ≥ 3.3 with [Prism](https://github.com/ruby/prism) — required for RSpec snapshot capture
  and cleanup. `scripts/ruby/digest_examples.rb` computes source digests;
  `scripts/ruby/delete_removed_examples.rb` deletes marked RSpec examples. Go-only
  projects do not require Ruby or Prism.
- Go — required for Go projects and the packaged standard-library source helpers.
  The helper module declares Go 1.23 syntax; compatibility is exercised with Go
  1.27.0 on darwin/arm64. Other Go versions/platforms require verification before
  claiming support. RSpec-only projects do not require Go.

**Claude Code — try it without installing** (one session only):

```bash
claude --plugin-dir /path/to/kaba
```

**Claude Code — install** from Kaba's self-hosted marketplace:

```bash
claude plugin marketplace add /path/to/kaba          # or a git URL once the repo is shared
claude plugin install kaba@kaba-marketplace -y
```

Claude's install defaults to `--scope user`, which enables the plugin — including its
`PreToolUse` guard — in **every project you open**, not just Kaba projects. The guard fails open
immediately in any repo without a `.kaba/config.yml`; pass `--scope project` instead to scope it
to one repo.

**Codex — install** from the same repository and marketplace:

```bash
codex plugin marketplace add /path/to/kaba
codex plugin add kaba@kaba-marketplace
```

Codex treats newly installed plugin hooks as untrusted until they are reviewed. Trust the Kaba
hooks only after checking the two commands in `hooks/hooks.json`; without that trust the skills
remain available, but the real-time hook feedback does not run.

## Get started

Run `/kaba:init` in Claude Code or `$kaba:init` in Codex once per repo. It inspects the project,
proposes a configuration, asks for your confirmation, then writes `.kaba/config.yml`, creates the
feature directory, and installs the git pre-commit hook shim that backs the enforcement described
below. It never commits on its own — the new `.kaba/` files need a commit from you.

## The command sequence

Run these roughly in order; `clarify`, `fix-tests`, and `research` are optional detours.

The table uses Claude Code syntax. In Codex, invoke the same skill explicitly as
`$kaba:<name>`; for example, `/kaba:plan-tests` becomes `$kaba:plan-tests`.

Every command that writes a feature artifact checks first whether that step has already completed,
and stops to ask before spending anything on a regeneration — feature artifacts are untracked at
that stage, so an accidental re-run would destroy the previous version with no way back. See
[Re-running a step](docs/workflow.md#re-running-a-step) for which commands gate and why `clarify`
and `fix-tests` deliberately do not.

| Command | What it does |
|---|---|
| `/kaba:init` | Detect the stack, confirm with you, write `.kaba/config.yml`, and wire the enforcement hooks. Run once per repo. |
| `/kaba:architecture` | Full codebase scan that (re)builds `.kaba/architecture.md` — the current-state doc every later command trusts. |
| `/kaba:specify` | Author or import a feature specification into the configured feature directory. |
| `/kaba:clarify` | *(optional)* Ask up to five targeted questions to close gaps in the spec before moving on. |
| `/kaba:acceptance-criteria` | Decompose the spec into granular, test-oriented acceptance criteria. |
| `/kaba:plan-tests` | Plan test organization — files, factories, helpers, criterion mapping, and the state-change allowlist. |
| `/kaba:implement-tests` | Write all test code following the test plan. Test files only, no implementation. |
| `/kaba:review-tests` | Review the locked test suite for strength: could a bad implementation still pass it? |
| `/kaba:fix-tests` | *(optional — only on a NO-GO review verdict)* Apply the review findings to the tests and re-validate. |
| `/kaba:plan-code` | Plan the implementation informed by the locked tests: components, schema, decisions, build order. |
| `/kaba:implement-code` | Write implementation code to make the locked tests green. Cannot edit test-owned files. |
| `/kaba:architecture-diff` | Fold the just-completed feature's architectural delta into `.kaba/architecture.md`. Mandatory at the end of every feature. |
| `/kaba:research` | *(outside the pipeline, human-triggered any time)* Investigate one open question and append a recommendation to the feature's research log. |

## What `.kaba/config.yml` controls

`/kaba:init` writes this file; hand-editing it afterward is the supported way to change settings.

| Key | Controls |
|---|---|
| `test_runner` | Adapter: `rspec` or `go`. Legacy configurations default to RSpec. |
| `test_write_allow` / `test_write_exclude` | Explicit test-session permissions; exclusions win. |
| `implement_write_allow` / `implement_write_exclude` | Explicit implementation-session permissions; exclusions win independently. |
| `test_dir` (legacy RSpec) | The test directory (e.g. `spec/`). The implementation session may never write here; the test session may write only here plus `feature_dir` and `test_writable`. |
| `test_command` | How the suite is run (e.g. `bundle exec rspec`). Drives every snapshot capture and gate. |
| `feature_dir` | Where feature artifacts live (e.g. `features/`) — spec, acceptance criteria, plans, snapshots. |
| `linter_command` | The project's aggregate quality command (e.g. `bundle exec rubocop` or `make verify`), run as an end gate in `/kaba:implement-code`. |
| `test_writable` *(optional)* | Extra paths the test session may write beyond `test_dir`/`feature_dir` — e.g. `Gemfile`, `Gemfile.lock` for a new test dependency. |
| `rules_files` *(optional)* | Which project-rules files (e.g. `CLAUDE.md`, `AGENTS.md`) commands read for non-negotiable constraints. |

Explicit configurations require `test_runner` and all four permission lists; allow
lists are nonempty and exclusion lists may be empty. Omit `test_dir` and
`test_writable` in this mode. Existing Rails configurations require no migration.
Patterns are repository-relative: `*` matches within a segment, `**` spans directories,
and a trailing `/` selects a subtree. These are independent wildcard lists; `.gitignore`
is not an ownership policy. Shared paths are writable in both sessions; excluded paths
remain denied in their respective session. Symlink checks intersect lexical and
resolved permissions. Renames check both endpoints.

```yaml
test_runner: go
test_command: go test ./...
linter_command: make verify
feature_dir: features/
rules_files: [AGENTS.md]
test_write_allow: ['**/*_test.go', '**/testdata/**', 'internal/testutil/**', 'features/**', 'go.mod', 'go.sum']
test_write_exclude: []
implement_write_allow: ['**']
implement_write_exclude: ['**/*_test.go', '**/testdata/**', 'internal/testutil/**']
```

Use the project's actual verification command. Go post-test scaffolds compile missing
production declarations through a validated temporary overlay. Post-implementation
captures execute only real code and protect all test-owned files, including ignored
fixtures, helpers, and scaffold sources. Every PIN requires overlay-free execution;
an overlay-assisted capture rejects all PINs. Between-feature cleanup removes exact
marked tests and recorded scaffold sources, verifies real tests, and restores bytes on
failure. Ordinary assertions, fakes, fixture files, and local HTTP stubs are supported
under project conventions; RSpec-specific matcher bans are inapplicable to Go.

## The enforcement model

Two layers, and they are not equally weighted:

- **The guarantee** is the pair of git-based checks: the pre-commit hook (`.kaba/hooks/pre-commit`,
  installed by `/kaba:init` via `core.hooksPath`) and the implementation session's end gates
  (snapshot compare + classifier-based ownership gate, run inline by `/kaba:implement-code`). Both inspect
  the working tree or the index, so they catch a violation no matter how it got there.
- **The `PreToolUse` guard** (`hooks/hooks.json`, self-registered by the plugin) is real-time
  feedback on path-declaring tool calls. It checks Claude's `Write`/`Edit`/`NotebookEdit` paths and
  every add/update/delete/move path in a Codex `apply_patch` call. It is a fast, cooperative layer
  on top of the guarantee, not a replacement for it — shell-based edits and `--no-verify` can
  bypass a real-time or commit-time check, so this is drift prevention for a cooperating agent,
  not security against a hostile one.

See [docs/workflow.md](docs/workflow.md) for the full pipeline, the snapshot comparison rules, and
the session-lock mechanics behind both layers.

## License

[MIT](LICENSE). See [NOTICE](NOTICE) for vendored spec-kit portions.
