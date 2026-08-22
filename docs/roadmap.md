# Kaba Roadmap

Kaba currently supports Claude Code with Rails/RSpec. This roadmap contains only future
work; completed user-visible changes are recorded in `CHANGELOG.md`.

## Codex compatibility

Codex is the next harness to validate. Do not restructure the repository into separate
adapter packages before that validation: both plugin formats can use one self-contained
plugin root, and the current enforcement core should stay shared unless a real incompatibility
proves otherwise.

### Working architecture

The default target is one package with two manifests and host-specific hook entry points:

```text
kaba/
├── .claude-plugin/
├── .codex-plugin/
├── skills/
├── hooks/
│   ├── claude.json
│   └── codex.json
├── scripts/
├── templates/
└── docs/
```

The repository root remains the plugin root, keeping every shipped script, template, skill,
and hook inside the installed package. Each manifest selects its own hook configuration; both
configurations delegate enforcement decisions to the same scripts. This preserves
`session-lock.sh`, snapshot enforcement, cleanup, configuration, and templates as one core
instead of copying them into hand-maintained adapter trees.

### Compatibility boundary to prove

The shared root does not mean the two harnesses behave identically. The Codex spike must resolve
these host-specific boundaries:

- **Packaging and discovery:** add `.codex-plugin/plugin.json` and a Codex marketplace entry,
  while keeping the existing Claude manifest and marketplace valid.
- **File-edit hooks:** Claude supplies direct Write/Edit paths. Codex aliases edits to
  `apply_patch` and supplies patch text in `tool_input.command`; the Codex guard must extract every
  added, updated, deleted, or moved path from a multi-file patch and check each one.
- **Session start:** the rewire must resolve the project from each host's hook payload (`cwd` in
  Codex) and point `kaba.scriptdir` at the active plugin root without requiring consumers to rerun
  `/kaba:init` after an update.
- **Skill invocation:** verify command names, explicit invocation, argument delivery, and
  invocation policy. Claude's `disable-model-invocation`, `context: fork`, and `$ARGUMENTS` are
  not assumed to have Codex semantics.
- **Review isolation:** reproduce the conversation-independent `/kaba:review-tests` boundary in
  Codex rather than silently running the review inline.
- **Hook trust and coverage:** verify plugin-hook trust, blocking output, subagent behavior, and
  every file-edit path Kaba depends on. Hooks remain cooperative feedback; the git pre-commit and
  end gates remain the guarantee.

### Compatibility spike

Before shipping Codex support:

1. Load the Claude and Codex manifests from the same repository root and confirm that both hosts
   discover the intended skills and hook configuration.
2. Exercise every skill explicitly, including arguments, re-run confirmation, and next-step
   handoffs.
3. Prove the Codex guard on single-file and multi-file add/update/delete/move patches, allowed and
   denied paths, malformed input, and missing configuration.
4. Prove SessionStart rewiring on first install and version update.
5. Prove `review-tests` runs without the implementer's conversation history while retaining disk,
   working-directory, project-rules, and hook access.
6. Run an end-to-end feature through both harnesses and observe every git and snapshot gate firing.

### Decision rule

If the spike passes, ship both harnesses from the shared root and keep the repository flat. If a
host difference cannot be expressed safely inside that package, introduce a build step that emits
self-contained `dist/claude/` and `dist/codex/` packages from shared source. Do not put the
marketplace root in a subdirectory while leaving runtime dependencies outside it, and do not
maintain duplicated core files by hand.

## Additional stack support

A second real stack consumer—not a target version—will determine the stack-adapter boundary.
Keep that decision separate from harness compatibility: Codex support must not force a speculative
test-framework abstraction, and a future non-RSpec stack must not require duplicating harness
packaging.
