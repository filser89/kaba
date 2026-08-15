# Kaba Roadmap

## Versioning

- **v1.0 — shipped.** What exists today: a Claude Code plugin for exactly one stack
  (Rails/RSpec), validated end-to-end by the acceptance run on markly (feature
  006-bookmark-favorites, 2026-08-15). One harness, one stack, on purpose (design D1).
- **v1.1 — hardening.** Fix what the acceptance run and platform review surfaced. Same
  scope as v1.0: no new harnesses, no new stacks — just making v1 solid. The backlog is
  below; the defect details live in `acceptance-findings.md`.
- **v2 — the adapter era.** A second harness (Codex) and/or a second stack, with the repo
  restructure that separation requires. Trigger: a second *real* consumer, not before —
  designing adapters against exactly one known consumer produces the wrong abstraction
  (design D1).

## v1.1 backlog

1. **F-1** — artifact-producing commands ask confirmation before overwriting prior-run
   output (clarify excepted while open questions remain). See `acceptance-findings.md`.
2. **F-2 + F-3** — test-plan.json allowlist schema v3: `{action, expected_landing}`
   entries (MODIFY/REMOVE/PIN/TOUCH), per-example AST digests in snapshots, and
   human-approved fix-tests escalations appending their own allowlist entries. One fix,
   two findings. See `acceptance-findings.md`.
3. **commands/ → skills/ migration.** Commands were merged into skills platform-side
   (not deprecated, no urgency). Migrating buys `disable-model-invocation: true` —
   mechanical user-invoke-only enforcement for the gated pipeline, plus 13 command
   descriptions removed from model context on every kaba-enabled project. Invocation
   (`/kaba:<name>`) and `hooks/hooks.json` are unchanged. Verify the `handoffs:`
   frontmatter carries over on ONE migrated file before doing the other twelve. Folds
   naturally into F-1's pass over the same 13 files.
4. **Release hygiene** (Task 13 deferred minors): plugin.json/marketplace.json duplicate
   version+description — bump both or the update silently no-ops; README overstates jq as
   required by every script (4 of 11 use it; the guard fails open without it);
   scripts/ruby needs its ruby 3.3+/Prism install caveat surfaced at install time.

## v2: adapters

### Why there is no `adapters/` directory yet

The approved design (§5) keeps the repo flat and puts portability in the *content*, not
the directory tree: across all 2,158 lines of command text there are only three
non-portable reference classes, and `session-lock.sh` — where every enforcement rule
lives — needs zero changes for Codex (design A.8). Pre-building the adapter seam against
one consumer would mean guessing where it goes. Also structural: the Claude Code plugin
loader requires `commands/` and `hooks/hooks.json` at the plugin ROOT, so Claude files
cannot be tucked into a subdirectory while the repo root IS the plugin.

### The Claude-specific inventory (what a claude adapter would encapsulate)

- `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json`
- `hooks/hooks.json` (PreToolUse declaration, `${CLAUDE_PLUGIN_ROOT}` paths)
- `scripts/session-lock-guard.sh` payload extraction only (~20–30 lines:
  `.tool_input.file_path // .tool_input.notebook_path` jq paths)
- command frontmatter conventions (`description`, `handoffs:`) and the `$ARGUMENTS`
  token (×12)
- prose: "PreToolUse guard" (×2), "subagents"

Everything else — all of `session-lock.sh`, the remaining scripts, all templates, the
command bodies — is harness-neutral.

### Codex port facts (design A.8, verified 2026-08)

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
│   ├── claude/     # .claude-plugin/, skills/ (or commands/), hooks/
│   │               #   ← marketplace source points here
│   └── codex/      # codex manifest, hook declaration, guard payload shim
├── scripts/        # harness-neutral core: session-lock, snapshot, config, …
├── templates/
└── docs/
```

Cost of restructuring: churns the validated plugin layout and every consumer's pinned
`kaba.scriptdir` (each must re-run `/kaba:init`). That cost is identical whenever it is
paid — so pay it exactly once, when the codex adapter actually exists.
