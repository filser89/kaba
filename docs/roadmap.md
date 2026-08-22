# Kaba Roadmap

## Versioning

- **v1.0 — shipped.** What exists today: a Claude Code plugin for exactly one stack
  (Rails/RSpec), validated end-to-end by the acceptance run on markly (feature
  006-bookmark-favorites, 2026-08-15). One harness, one stack, on purpose.
- **v1.1 — hardening.** Fix what the acceptance run and platform review surfaced. Same
  scope as v1.0: no new harnesses, no new stacks — just making v1 solid. The backlog is
  below; the defect details live in `acceptance-findings.md`.
- **v2 — the adapter era.** A second harness (Codex) and/or a second stack, with the repo
  restructure that separation requires. Trigger: a second *real* consumer, not before —
  designing adapters against exactly one known consumer produces the wrong abstraction.

## v1.1 backlog

### Shipped

- **commands/ → skills/ migration** (2026-08-18). All thirteen moved to
  `skills/<name>/SKILL.md`, each carrying a `name:` key matching its directory. Invocation
  (`/kaba:<name>`) and `hooks/hooks.json` are unchanged, and `plugin.json` needed no edit —
  `skills/` is scanned by default. `disable-model-invocation: true` on all thirteen, which
  also drops their descriptions from model context in every project the plugin is enabled in.
  The nine `handoffs:` blocks — a VS Code custom-agents key, inert in Claude Code, inherited
  from spec-kit — are gone, replaced by `## Next Step` prose in the ten skills that would
  otherwise end on nothing; the three that had omitted `send: true` (`architecture`,
  `architecture-diff`, `research`) ask the human for input rather than presenting the next
  step as automatic. `test/commands_test.sh` → `test/skills_test.sh`, driven off the
  `EXPECTED` name list rather than a `skills/*/SKILL.md` glob, so a directory missing its
  `SKILL.md` fails loudly instead of dropping out of the matrix into a green suite. `NOTICE`
  retargeted — and `test/manifest_test.sh`'s NOTICE-path extractor widened, since its old
  `[a-z-]*/[a-z-]*\.md` pattern would have matched nothing against the new paths and checked
  nothing while still reporting green.

  **`review-tests` runs `context: fork`.** Spiked before adopting, since the key is
  undocumented in plugin-dev's frontmatter reference — full findings in `manifest-findings.md`.
  A forked skill's tool calls never enter the parent transcript; PreToolUse hooks still fire
  for them and a denial still blocks them, so the session-lock guard is not weakened. The
  surprise: a fork does **not** inherit the conversation — the opposite of the Agent tool's
  identically-named `subagent_type: "fork"`. For the adversarial test gate that blindness is
  the feature: a reviewer that cannot see the implementer's reasoning cannot be talked out of
  a finding by it. `fix-tests` is the tempting second candidate and must not follow — it
  resolves escalated findings interactively with the human, which a fork cannot do.

  For the record, this item's original rationale was wrong: it claimed the migration is what
  buys `disable-model-invocation`. That key works in `commands/*.md` too. The real arguments
  were the legacy layout and the skill-only frontmatter keys — of which `context: fork` is the
  one that actually paid.

- **Allowlist schema v3 — F-2 + F-3** (2026-08-19). One vocabulary fix closes both
  acceptance findings: `test-plan.json` entries are now `{action, expected_landing}`
  over MODIFY/REMOVE/PIN/TOUCH (PIN: expected-green new examples, identified by file +
  exact planned description — F-2; TOUCH: status-preserving content edits — F-3).
  Snapshots are version 2 with per-example Prism AST digests
  (`scripts/ruby/digest_examples.rb`; formatting-immune, loop groups share one digest),
  so a content edit with no status flip is now a compare violation unless allowlisted.
  Two mechanical guards landed with it: validate-plan writes
  `snapshots/test-plan.lock.json` and compare rejects any in-session plan edit that
  isn't a provenance-stamped `allowlist-append` (the new snapshot-tests.sh mode
  fix-tests runs on human-approved escalations — TOUCH/MODIFY only; REMOVE/PIN stay
  plan-time). Migration is a clean break: v1 snapshots and v2 plans are rejected
  loudly — a feature mid-flight finishes on kaba v1.0 or restarts its test session.
  The compare rule matrix finally has behavioral tests
  (`test/snapshot_compare_test.sh`, fixture-driven). Design:
  `docs/superpowers/specs/2026-08-19-allowlist-schema-v3-design.md` (untracked).

### Remaining

1. **Release hygiene** (deferred minors from the extraction): README overstates jq as required by every
   script (4 of 11 use it; the guard fails open without it); scripts/ruby needs its
   ruby 3.3+/Prism install caveat surfaced at install time.

## v2: adapters

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
