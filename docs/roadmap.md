# Kaba Roadmap

Kaba currently supports Claude Code with Rails/RSpec. This roadmap contains only future
work; completed user-visible changes are recorded in `CHANGELOG.md`.

## Adapter support

A second harness (Codex) and/or a second stack will trigger the repository restructure
that separation requires. The trigger is a second *real* consumer, not a target version:
designing adapters against exactly one known consumer produces the wrong abstraction.

### Why there is no `adapters/` directory yet

The design keeps the repo flat and puts portability in the *content*, not
the directory tree: across all 2,102 lines of skill text there are only three
non-portable reference classes, and `session-lock.sh` — where every enforcement rule
lives — needs zero changes for Codex (see the port facts below). Pre-building the adapter seam against
one consumer would mean guessing where it goes.

**Correction (2026-08-17):** this section used to add a structural argument — that the
loader requires `commands/` and `hooks/hooks.json` at the plugin root, so Claude files
could not be tucked into a subdirectory. That is not true, and the reasoning should not
lean on it. Per `manifest-findings.md`, `plugin.json`'s `commands` field takes custom
paths and *replaces* the default scan, `skills` *adds* to it and even accepts `"."` for
the plugin root, and `hooks` may point elsewhere or be inlined. Only `plugin.json` itself
must sit at `.claude-plugin/`. Component directories are therefore relocatable today, and
the marketplace entry can point at a subdirectory regardless. What remains — and it is
enough on its own — is that designing an adapter seam against exactly one known consumer
produces the wrong abstraction.

### The Claude-specific inventory (what a claude adapter would encapsulate)

- `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json`
- `hooks/hooks.json` (PreToolUse declaration, `${CLAUDE_PLUGIN_ROOT}` paths)
- `scripts/session-lock-guard.sh` payload extraction only (~20–30 lines:
  `.tool_input.file_path // .tool_input.notebook_path` jq paths)
- skill frontmatter conventions (`name`, `description`, `disable-model-invocation`,
  `context: fork`) and the `$ARGUMENTS` token (×12)
- prose: "PreToolUse guard" (×2), "subagents" (×1)

Everything else — all of `session-lock.sh`, the remaining scripts, all templates, the
skill bodies — is harness-neutral.

### Codex port facts (verified 2026-08)

- PreToolUse-equivalent hooks: supported; block convention identical (exit 2 + stderr,
  or `permissionDecision: "deny"` JSON)
- Config: `~/.codex/hooks.json` or `.codex/config.toml`; payload is
  `tool_name` + `tool_input`
- Packaging: Codex has a plugin system with bundled hooks — symmetric to Claude's
- **Caveat**: openai/codex#20204 (inconsistent hook coverage across handlers) was still
  open at design time. Smoke-test the guard on install; a guard that silently doesn't
  fire is worse than no guard.

### Repo restructure sketch (do once, with the second adapter in hand)

Point the marketplace entry at a subdirectory instead of the repo root:

```
kaba/
├── adapters/
│   ├── claude/     # .claude-plugin/, skills/, hooks/
│   │               #   ← marketplace source points here
│   └── codex/      # codex manifest, hook declaration, guard payload shim
├── scripts/        # harness-neutral core: session-lock, snapshot, config, …
├── templates/
└── docs/
```

Cost of restructuring: churns the validated plugin layout and every consumer's pinned
`kaba.scriptdir` (each must re-run `/kaba:init`). That cost is identical whenever it is
paid — so pay it exactly once, when the codex adapter actually exists.
