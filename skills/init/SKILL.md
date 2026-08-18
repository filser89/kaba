---
name: init
description: Onboard this project onto kaba — detect the stack, confirm with the user, then write .kaba/config.yml and wire the enforcement hooks.
---

Onboard this repository onto kaba. Detection and confirmation are your job; writing files is
`scripts/init-project.sh`'s job. Never write `.kaba/config.yml` by hand, and never guess past an
ambiguity — ask instead.

## 1. Check for an existing config first

Look for `.kaba/config.yml`. If it exists, say so, stop, and tell the user hand-editing the file
is the supported way to change settings. Only proceed past this point if the user explicitly
asks to start over — in that case you will pass `--force` in step 5.

## 2. Detect the stack and show your reasoning

Inspect the repository and propose values, showing the user what you found and why for each one:

- **Test directory** — look for `spec/` or `test/` at the repo root.
- **Test command** — propose `bundle exec rspec` if `.rspec` or `spec/spec_helper.rb` exists.
- **Linter command** — propose `bundle exec rubocop` if `.rubocop.yml` exists.
- **Rules files** — check for `CLAUDE.md` and `AGENTS.md`; include whichever exist.
- **Runner artifacts** — grep `spec/spec_helper.rb` for `example_status_persistence_file_path` and
  read the path it points at (e.g. `spec/examples.txt`); propose gitignoring it.
- **Feature directory** — propose `features/`.

Do not guess when detection is ambiguous — e.g. both `spec/` and `test/` are present, or no
recognizable test runner is found. Ask the user to pick instead of choosing for them.

## 3. Guard the feature directory

If the proposed feature directory already exists and is non-empty, stop and ask before doing
anything else. On a Rails project in particular, a pre-existing `features/` very likely belongs to
Cucumber — look for `*.feature` files or a `cucumber` gem to confirm the suspicion, then propose a
different directory name to the user rather than adopting it. `init-project.sh` itself refuses to
write into a non-empty feature directory without `--force`, so asking the user for a different name
is the only way through this case.

## 4. Get explicit confirmation

Present the full proposed configuration — test dir, test command, linter command, rules files,
runner artifacts, feature dir — and get the user's explicit go-ahead before writing anything. Adjust
any value the user pushes back on and re-confirm.

## 5. Call the script — never write the config by hand

Run `scripts/init-project.sh` with the confirmed values, e.g.:

```
scripts/init-project.sh --test-dir spec/ --test-command "bundle exec rspec" \
  --feature-dir features/ --linter-command "bundle exec rubocop" \
  --test-writable "Gemfile,Gemfile.lock" --rules-files "CLAUDE.md" \
  --runner-artifact "spec/examples.txt"
```

Pass `--force` only if the user explicitly asked to overwrite an existing config or adopt a
non-empty feature directory. The script does all the writing: it creates the feature directory,
installs the pre-commit hook shim, points `core.hooksPath` at it, sets `kaba.scriptdir`, and
gitignores runner artifacts. If it fails, report its error verbatim — do not work around it by
writing files yourself.

## 6. Report and hand off

Summarize what was written (config path, feature dir, hook shim). Remind the user that `/kaba:init`
never commits — the new `.kaba/` files (config and hook shim) need a commit from them. Point them at
`/kaba:specify <one-liner>` as the next step.
