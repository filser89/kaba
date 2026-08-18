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

1. **F-2 + F-3** — test-plan.json allowlist schema v3: `{action, expected_landing}`
   entries (MODIFY/REMOVE/PIN/TOUCH), per-example AST digests in snapshots, and
   human-approved fix-tests escalations appending their own allowlist entries. One fix,
   two findings. See `acceptance-findings.md`.
2. **commands/ → skills/ migration.** Commands were merged into skills platform-side
   (not deprecated, no urgency). Invocation (`/kaba:<name>`) and `hooks/hooks.json` are
   unchanged: skills namespace off the *directory* name, so `skills/init/SKILL.md` still
   gives `/kaba:init`. Verified layout facts are in `manifest-findings.md` — directory per
   skill, no flat `skills/<name>.md` form, `$ARGUMENTS` works, no manifest change needed
   since `skills/` is scanned by default.

   **Why, since the original rationale was wrong.** This item used to claim migrating buys
   `disable-model-invocation: true`. It does not — that key works in `commands/*.md` today
   (see `manifest-findings.md`). The real arguments are that `commands/` is the legacy
   layout and that skills support frontmatter keys commands cannot: `when_to_use`, `paths`,
   `hooks`, `context: inline|fork`, `agent`, `background`. `context: fork` is the concrete
   lever — `review-tests` is read-only and self-contained, exactly the shape that wants a
   forked subagent rather than the main conversation.

   **Scope, carried over from the F-1 pass** (deferred there only to avoid touching the same
   13 files twice):
   - Add `disable-model-invocation: true` to all thirteen. The pipeline is a chain of human
     gates, and `implement-tests`/`implement-code` arm and clear the session lock — a model
     that fires one on its own can disarm the two-session boundary. The flag also drops all
     13 descriptions from model context (spike-verified; see `manifest-findings.md`), in
     every project the plugin is enabled in.
   - **Delete the nine `handoffs:` blocks and add prose next-step pointers.** There is no
     handoffs carryover to verify: the key is a VS Code custom-agents feature, inert in
     Claude Code, inherited from spec-kit's multi-target templates (`manifest-findings.md`).
     Ten of thirteen commands consequently end with no next-step guidance at all — only
     `specify.md`, `init.md`, and `fix-tests.md` say it in prose. Each pointer should carry
     the intent of the handoff it replaces, and the three that omitted `send: true`
     (`architecture`, `architecture-diff`, `research`) meant "the human edits this before it
     runs" — preserve that by asking for input rather than presenting the step as automatic.
   - Rewrite `test/commands_test.sh` → `test/skills_test.sh`. Under bash the unmatched glob
     at its per-file loop stays literal, so the move fails loudly (~20 red assertions), not
     silently. The risk is in the *fix*: driving the loop from a `skills/*/SKILL.md` glob
     means a directory missing its `SKILL.md` yields a green suite with that skill
     unchecked. Drive the matrix from the `EXPECTED` name list and assert it ran 13 times.
     Worth adding then: `name:` matches the directory, and no file-relative `../templates`
     path exists — everything routing through `$(git config kaba.scriptdir)` is precisely
     what makes moving the files safe.
   - `NOTICE` names `commands/specify.md` and `commands/clarify.md`; retarget it.
3. **Release hygiene** (deferred minors from the extraction): README overstates jq as required by every
   script (4 of 11 use it; the guard fails open without it); scripts/ruby needs its
   ruby 3.3+/Prism install caveat surfaced at install time.

## v2: adapters

### Why there is no `adapters/` directory yet

The design keeps the repo flat and puts portability in the *content*, not
the directory tree: across all 2,158 lines of command text there are only three
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
- command frontmatter conventions (`description`, `handoffs:`) and the `$ARGUMENTS`
  token (×12)
- prose: "PreToolUse guard" (×2), "subagents"

Everything else — all of `session-lock.sh`, the remaining scripts, all templates, the
command bodies — is harness-neutral.

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
