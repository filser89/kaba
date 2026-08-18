# kaba

kaba is a Claude Code plugin that ships a **mechanically-enforced spec-driven TDD workflow** —
not a prompt pack. The two-session split (tests first, implementation second) and the boundary
between them are held by git hooks and pass/fail scripts, not by asking the agent nicely. See
[docs/workflow.md](docs/workflow.md) for the full pipeline and the reasoning behind it.

**v1 targets Rails/RSpec projects.** The scripts themselves are generic bash + git, but the
conventions they assume (`bundle exec rspec`, `bundle exec rubocop`, RSpec's `receive` /
`expect_any_instance_of` banned patterns, an RSpec-file AST helper for test cleanup) are Rails
shaped. Other stacks are out of scope for now.

## Install

**Dependencies:**

- `git` ≥ 2.28 and `jq` — required for every command and script.
- `ruby` ≥ 3.3 — required only for `scripts/cleanup-tests.sh`, which uses
  `scripts/ruby/delete_removed_examples.rb` to delete skip-marked-for-removal RSpec examples via
  [Prism](https://github.com/ruby/prism) (Ruby's own parser, stdlib since 3.3). Everything else
  ships with no Ruby dependency.

**Try it without installing** — loads the plugin for one session only:

```bash
claude --plugin-dir /path/to/kaba
```

**Real install**, via kaba's self-hosted marketplace (the same repo doubles as its own
marketplace catalog):

```bash
claude plugin marketplace add /path/to/kaba          # or a git URL once the repo is shared
claude plugin install kaba@kaba-marketplace -y
```

Install defaults to `--scope user`, which enables the plugin — including its `PreToolUse`
guard — in **every project you open**, not just kaba projects. The guard fails open immediately
in any repo without a `.kaba/config.yml`, so this is safe, but pass `--scope project` instead if
you want the plugin scoped to one repo.

## Get started: `/kaba:init`

Run `/kaba:init` once per repo. It inspects the project, proposes a configuration, asks for your
confirmation, then writes `.kaba/config.yml`, creates the feature directory, and installs the
git pre-commit hook shim that backs the enforcement described below. It never commits on its own
— the new `.kaba/` files need a commit from you.

## The command sequence

Run these roughly in order; `clarify`, `fix-tests`, and `research` are optional detours.

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
| `/kaba:implement-code` | Write implementation code to make the locked tests green. Cannot touch the test directory. |
| `/kaba:architecture-diff` | Fold the just-completed feature's architectural delta into `.kaba/architecture.md`. Mandatory at the end of every feature. |
| `/kaba:research` | *(outside the pipeline, human-triggered any time)* Investigate one open question and append a recommendation to the feature's research log. |

## What `.kaba/config.yml` controls

`/kaba:init` writes this file; hand-editing it afterward is the supported way to change settings.

| Key | Controls |
|---|---|
| `test_dir` | The test directory (e.g. `spec/`). The implementation session may never write here; the test session may write only here plus `feature_dir` and `test_writable`. |
| `test_command` | How the suite is run (e.g. `bundle exec rspec`). Drives every snapshot capture and gate. |
| `feature_dir` | Where feature artifacts live (e.g. `features/`) — spec, acceptance criteria, plans, snapshots. |
| `linter_command` | The project's linter (e.g. `bundle exec rubocop`), run as an end gate in `/kaba:implement-code`. |
| `test_writable` *(optional)* | Extra paths the test session may write beyond `test_dir`/`feature_dir` — e.g. `Gemfile`, `Gemfile.lock` for a new test dependency. |
| `rules_files` *(optional)* | Which project-rules files (e.g. `CLAUDE.md`, `AGENTS.md`) commands read for non-negotiable constraints. |

## The enforcement model

Two layers, and they are not equally weighted:

- **The guarantee** is the pair of git-based checks: the pre-commit hook (`.kaba/hooks/pre-commit`,
  installed by `/kaba:init` via `core.hooksPath`) and the implementation session's end gates
  (snapshot compare + test-directory-untouched, run inline by `/kaba:implement-code`). Both inspect
  the working tree or the index, so they catch a violation no matter how it got there.
- **The `PreToolUse` guard** (`hooks/hooks.json`, self-registered by the plugin — no
  `settings.json` edit required) is real-time feedback on path-declaring tool calls: it blocks the
  agent's own `Write`/`Edit`/`NotebookEdit` calls to locked paths at the moment of the edit. It is
  a fast, cooperative layer on top of the guarantee, not a replacement for it — `--no-verify` can
  bypass the pre-commit hook, and both checks run inside the same session they police, so this is
  drift prevention for a cooperating agent, not security against a hostile one.

See [docs/workflow.md](docs/workflow.md) for the full pipeline, the snapshot comparison rules, and
the session-lock mechanics behind both layers.

## License

[MIT](LICENSE). See [NOTICE](NOTICE) for vendored spec-kit portions.
