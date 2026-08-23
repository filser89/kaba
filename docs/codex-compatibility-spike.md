# Codex Compatibility Spike

**Date:** 2026-08-23
**Hosts:** Codex CLI 0.149.0, Claude Code 2.1.238
**Decision:** Keep one flat, self-contained plugin root. No adapter packages or build step are
needed for the validated mechanisms.

## What the spike proved

### Packaging and discovery

- `.codex-plugin/plugin.json` and `.claude-plugin/plugin.json` coexist at the repository root.
- Codex can register the repository itself as a marketplace, parse the existing
  `.claude-plugin/marketplace.json`, install `kaba@kaba-marketplace`, and cache the entire root.
  A second Codex-only marketplace file is unnecessary.
- Codex discovered all thirteen shared skills as `kaba:<skill>` and auto-discovered
  `hooks/hooks.json`. The Codex manifest therefore omits a `hooks` field; the installed schema and
  plugin validator do not accept it.
- Each skill carries Codex-specific `agents/openai.yaml` metadata with
  `policy.allow_implicit_invocation: false`, preserving Kaba's human-triggered workflow alongside
  Claude's `disable-model-invocation: true` frontmatter.

Validated CLI flow:

```bash
codex plugin marketplace add /path/to/kaba
codex plugin add kaba@kaba-marketplace
codex plugin list --marketplace kaba-marketplace --available --json
```

### File-edit enforcement

Codex matches edits as `apply_patch` and passes the complete patch in `tool_input.command`. The
shared guard now extracts every `Add File`, `Update File`, `Delete File`, and `Move to` path and
checks all of them through `session-lock.sh`.

The automated matrix covers single- and multi-file patches, allowed and denied paths, adds,
updates, deletes, moves, malformed patches, missing Kaba configuration, and the original Claude
direct-path payloads. A real nested Codex run attempted to add `app/models/blocked.rb` during a
test session; the hook returned the named session-lock violation and the file was not created.

### SessionStart rewiring

Claude continues to provide its project and plugin-root environment variables. Codex supplies the
project as `cwd`; the installed script derives its plugin root from its own location. Tests cover
both payloads, and live cachebuster installs confirmed that `kaba.scriptdir` followed the active
Codex cache path after an update.

### Skill invocation and review isolation

Codex explicitly invoked the reviewer as `$kaba:review-tests` and delivered `GREET-001` as a scoped
argument. An ordinary planning prompt did not inject Kaba, confirming the explicit-only policy.

Codex does not honor Claude's `context: fork` frontmatter. The first two-turn probe placed a secret
only in the implementer's prior turn; the inline reviewer reproduced that secret in its report.
Kaba now bridges the boundary explicitly: the Codex parent spawns one reviewer with
`fork_turns: "none"`, passes only invocation arguments, waits, and relays the result. Repeating the
same probe hid the secret, while the reviewer retained the working directory, project rules,
installed scripts, hook access, and disk artifacts needed to write `test-review.md`.

### Hook trust

Codex discovered installed plugin hooks in an untrusted state. The automated live checks used the
CLI's explicit trust bypass only for disposable fixtures. Normal users must review and trust the
hook commands before real-time feedback can run; the git pre-commit and end gates remain the
mechanical guarantee.

## Remaining release validation

The spike exercised the host-specific mechanisms and one representative skill end to end. It did
not run all thirteen skill bodies or a complete dual-host feature pipeline. Those release checks
remain in `docs/roadmap.md`.
