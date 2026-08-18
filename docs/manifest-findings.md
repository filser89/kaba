# Plugin manifest & hook self-registration — verified findings

Produced by Task 1 (gate spike) of the kaba extraction, 2026-08-13.
Every claim below is backed by a fetched doc passage or a command run on this machine.
Tasks 8 and 13 should read this file rather than re-deriving it.

**How to read this doc — two evidence tiers, and they are labeled.** *Spike-observed* means a command
was run on this machine and its output is reproduced here; build on those directly. *Doc-only* means
the claim comes from documentation the spike never exercised — plausible, but verify before you
depend on it. Where the two are mixed in one section, the section splits them under explicit
headings. Doc passages presented in quotation marks are verbatim and were re-fetched and checked
character-for-character on 2026-08-13.

**Environment of record:** `claude` CLI **2.1.231**, macOS (darwin 25.5.0), `jq` 1.7.1.
Plugin schemas move; re-verify against a newer CLI before trusting this for a different version.

**Sources fetched (2026-08-13):**
- https://code.claude.com/docs/en/plugins
- https://code.claude.com/docs/en/plugin-marketplaces
- https://code.claude.com/docs/en/hooks
- https://code.claude.com/docs/en/plugins-reference (linked from the above as the "full manifest schema")

**Spike used:** `/tmp/kaba-spike` (plugin `kaba-spike`, one command, one PreToolUse hook), plus a
local marketplace at `/tmp/kaba-marketplace` and three throwaway git projects
`/tmp/kaba-test-{a,b,c}`. All deleted after these findings were recorded.

---

## (a) `plugin.json` — location, required fields, schema

**Location:** `<plugin-root>/.claude-plugin/plugin.json`.

**Required fields: `name` only.** Quoted verbatim from plugins-reference (re-fetched 2026-08-13):

> "If you include a manifest, `name` is the only required field."

> "The manifest is optional. If omitted, Claude Code auto-discovers components in [default
> locations](#file-locations-reference) and derives the plugin name from the directory name. Use a
> manifest when you need to provide metadata or custom component paths."

The same page's file-locations table gives the path verbatim as
`| **Manifest** | `.claude-plugin/plugin.json` | Plugin metadata and configuration (optional)`.
kaba should ship a manifest regardless — it needs the metadata, and relying on directory-name
inference would make the `/kaba:` namespace depend on what the consumer's checkout is called.

`name` must be kebab-case with no spaces, and it is the namespace prefix for every component the
plugin ships.

The manifest the spike used, which passed `claude plugin validate` (warning only, about a missing
`author`):

```json
{
  "name": "kaba-spike",
  "description": "Throwaway spike: verify manifest shape and hook self-registration",
  "version": "0.0.1"
}
```

```
$ claude plugin validate /tmp/kaba-spike
Validating plugin manifest: /tmp/kaba-spike/.claude-plugin/plugin.json

⚠ Found 1 warning:

  ❯ author: No author information provided. Consider adding author details for plugin attribution

✔ Validation passed with warnings
```

**Fields relevant to kaba** (from plugins-reference; all optional unless marked):

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | **Yes** | kebab-case. Namespace prefix for all components. For kaba: `"kaba"`. |
| `description` | string | No | Shown in the plugin manager. |
| `version` | string | No | Semver. If set, users only get updates when it is bumped. |
| `author` | object | No | `{name, email, url}`. Omitting it is a validate **warning** — set it, since `--strict` turns warnings into errors and the community-marketplace review pipeline runs the same check. |
| `displayName` | string | No | Human-readable UI name; defaults to `name`. |
| `homepage`, `repository`, `license`, `keywords` | string/array | No | Metadata. |
| `defaultEnabled` | boolean | No | Defaults to `true`. Set `false` to ship disabled. |
| `commands` | string/array | No | Custom command paths. **Replaces** the default `commands/` scan. |
| `skills` | string/array | No | Custom skill dirs. **Adds to** the default `skills/` scan. |
| `hooks` | string/array/object | No | Path(s) to hook config, or inline config. Has its own merge rules. |
| `agents`, `mcpServers`, `lspServers`, `outputStyles` | various | No | Component overrides. |
| `userConfig` | object | No | Values prompted at enable time; exported to hook processes as `CLAUDE_PLUGIN_OPTION_<KEY>`. |
| `dependencies` | array | No | Other plugins, optionally semver-constrained. |

All manifest paths must be relative and start with `./` (the sole exception: `skills` also accepts
`"."` for the plugin root).

**Layout rule (a documented common mistake):** only `plugin.json` goes inside `.claude-plugin/`.
`commands/`, `skills/`, `agents/`, `hooks/`, `scripts/`, `.mcp.json` all live at the **plugin root**.

---

## (b) Hook self-registration — YES, verified

**A plugin-bundled PreToolUse hook fires with no `hooks` key anywhere in the consumer's settings.**

**Declaring file:** `<plugin-root>/hooks/hooks.json` (default location).
**Declaring field:** the top-level `hooks` object inside that file — same shape as the `hooks` object
in `.claude/settings.json`. A `description` sibling key is allowed.
**Alternative:** `plugin.json`'s optional `hooks` field may point elsewhere (string path, array of
paths, or an inline object). The spike used the default `hooks/hooks.json` and did **not** need a
`hooks` entry in `plugin.json`.

The exact file the spike shipped:

```json
{
  "description": "Spike guard: proves a plugin-bundled PreToolUse hook self-registers",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/scripts/spike-guard.sh",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

**Path variable:** `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin's installed directory and **changes
on update** — after a marketplace install it resolved under the versioned cache:

```
/Users/serg/.claude/plugins/cache/kaba-spike-market/kaba-spike/0.0.1/
```

Quote it as `"${CLAUDE_PLUGIN_ROOT}"/scripts/x.sh` (the docs' own form) — the cache path contains a
version segment and could contain spaces. For data that must survive updates use
`${CLAUDE_PLUGIN_DATA}` instead.

### Verification: the write was blocked, settings.json never touched

Test project `/tmp/kaba-test-a` had **no `.claude/` directory at all** (so no `hooks` key was even
possible), and `~/.claude/settings.json` had **no `hooks` key** (`jq '.hooks' → "ABSENT"`). Asking a
fresh session to write `SPIKE_BLOCKED.txt`:

```
PreToolUse:Write hook error: ["${CLAUDE_PLUGIN_ROOT}"/scripts/spike-guard.sh]: spike-guard: blocked /private/tmp/kaba-test-a/SPIKE_BLOCKED.txt
```

The file was not created (`ls` → `No such file or directory`), and the guard's **stderr text reached
the agent verbatim** as the blocking reason.

The same held after a real (non-`--plugin-dir`) install. Project-scope install wrote **only** this
into the consumer's `.claude/settings.json` — note the absence of any `hooks` key:

```json
{
  "enabledPlugins": {
    "kaba-spike@kaba-spike-market": true
  }
}
```

**Negative control** (proves the hook is selective, not that writing is broken): in the same session
configuration, writing `SPIKE_OK.txt` succeeded — `-rw-r--r-- 1 serg wheel 5 ... SPIKE_OK.txt`.

### PreToolUse contract — spike-observed

Each bullet here was exercised by the spike runs recorded above. These are safe to build on directly.

- Input arrives as **JSON on stdin**; `.tool_input.file_path` is the Write/Edit target. The spike's
  `jq -r '.tool_input.file_path // empty'` extracted it correctly — the blocking message echoed the
  full, correct path (`/private/tmp/kaba-test-a/SPIKE_BLOCKED.txt`).
- **Exit 2 blocks the tool call**, and the hook's **stderr is surfaced to the model verbatim** as the
  reason. Observed as
  `PreToolUse:Write hook error: [<command>]: spike-guard: blocked <path>`, with the file never created.
- **Exit 0 lets the tool proceed.** Observed via the negative control: on the `SPIKE_OK.txt` write the
  guard ran, took its `[[ … ]] || exit 0` branch, and the write succeeded. **This is the shape kaba's
  fail-open guard must use when `.kaba/config.yml` is absent.**
- A `"matcher": "Write|Edit"` **matches the `Write` tool** — plain tool names with `|` alternation
  work as written.

### PreToolUse contract — doc-only (NOT exercised by the spike)

These come from https://code.claude.com/docs/en/hooks and
https://code.claude.com/docs/en/plugins-reference. They are plausible and load-bearing for later
design, but **nothing below was tested by this spike** — verify before depending on any of it.

- A structured alternative to exit 2 is documented: print
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"…"}}`
  on stdout, where `permissionDecision` accepts `deny|allow|escalate`. The spike used the exit-2 +
  stderr path only.
- Matcher regex mode: the docs say any character beyond letters, digits, `_`, `-`, spaces, `,` and `|`
  switches the matcher to regex. The spike only used the literal `Write|Edit` form.
- Plugin hooks are documented to fire **inside subagents**, with `agent_id` / `agent_type` added to
  the hook input. The spike never ran a subagent.
- On exit 0, stderr is documented to go to the debug log only and never reach the model. The spike's
  exit-0 path printed nothing to stderr, so this routing was not observed.
- Shell-form plugin hook commands are documented as unable to reference `${user_config.*}` (use exec
  form via `args`, or read `$CLAUDE_PLUGIN_OPTION_<KEY>`). The spike declared no `userConfig`.

---

## (c) Command invocation format — `/<plugin-name>:<file-basename>`

**Verified.** The spike shipped `commands/kaba.ping.md` in plugin `kaba-spike`. A fresh session
reported its available-skills entry verbatim as:

```
- kaba-spike:kaba.ping: Spike command — proves plugin commands register
```

and `/kaba-spike:kaba.ping` replied `PONG`. `claude plugin details kaba-spike` lists it as:

```
Component inventory
  Skills (1)  kaba.ping
  Hooks (1)  PreToolUse  (harness-only — no model context cost)
```

**Control:** with the plugin *not* loaded, both `/kaba-spike:kaba.ping` and `/kaba.ping` failed —
`the Skill tool returned "Unknown skill: kaba.ping"`. So the PONGs above were real registration, not
the model guessing a ping/pong reply.

**Consequence for kaba — this is the decisive finding.** Namespacing is unconditional; the docs state
plugin skills are *"always namespaced … to prevent conflicts"*. A file named `kaba.init.md` inside a
plugin named `kaba` therefore surfaces as **`/kaba:kaba.init`** — the stutter the plan feared.

> **Rule: kaba's command files drop the `kaba.` prefix.** `commands/init.md` → `/kaba:init`,
> `commands/specify.md` → `/kaba:specify`, and so on.

Secondary observations:

- The unqualified form (`/kaba.ping`) also resolved while the plugin was loaded, but the **canonical,
  listed** name is the namespaced one. Do not depend on the bare form — it is what collides with
  same-named project commands.
- Subdirectories under `commands/` are **not** scanned for nested `.md` files. Every command file must
  sit directly in `commands/` (or be named explicitly in the manifest's `commands` array). kaba's
  command set must therefore be flat.
- **`skills/` namespaces identically**, using the *directory* name. Adding
  `skills/pingskill/SKILL.md` to the same spike produced
  `- kaba-spike:pingskill: Spike skill — proves skills/ layout naming`. So `skills/init/SKILL.md`
  would also give `/kaba:init`. The docs describe `commands/` as *"Skills as flat Markdown files. Use
  `skills/` for new plugins"* — **flagged for Task 8**: `commands/` works today (verified) but is the
  older layout, and the manifest's `commands` field *replaces* the default scan while `skills` *adds*
  to it. Either layout satisfies the naming rule above.

---

## (d) Hook enablement scope — follows the `enabledPlugins` entry's settings file

**Verified across three projects, both scopes.** A plugin-bundled hook fires in **every project where
the plugin is enabled**, and enablement is recorded as an `enabledPlugins` entry keyed
`"<plugin>@<marketplace>": true`. Which settings file holds that entry decides the blast radius.

**The primary evidence is the Phase 1 / Phase 2 testing below, not a doc claim.** No documentation
page states the blast radius of a plugin-bundled hook in a single sentence; the answer is composed
from two doc tables plus the empirical result. Both passages below were re-fetched and quoted
verbatim on 2026-08-13.

The hooks page establishes *when* a plugin hook is in effect, but not *which* projects. Its
hook-locations table has three columns (Location, Scope, Shareable); the plugin row verbatim:

```
| Location                                      | Scope                  | Shareable                    |
| [Plugin](/docs/en/plugins) `hooks/hooks.json` | When plugin is enabled | Yes, bundled with the plugin |
```

— https://code.claude.com/docs/en/hooks

The plugins-reference page supplies the other half — which settings file each install scope writes
to. Under the heading **"Plugin installation scopes"**: *"When you install a plugin, you choose a
**scope** that determines where the plugin is available and who else can use it"*, followed verbatim by:

```
| Scope     | Settings file                                        | Use case                                                                    |
| :-------- | :--------------------------------------------------- | :-------------------------------------------------------------------------- |
| `user`    | `~/.claude/settings.json`                            | Personal plugins available across all projects (default)                    |
| `project` | `.claude/settings.json`                              | Team plugins shared via version control                                     |
| `local`   | `.claude/settings.local.json`                        | Project-specific plugins, gitignored when Claude Code saves a setting to it |
| `managed` | [Managed settings](/docs/en/settings#settings-files) | Managed plugins (read-only, update only)                                    |
```

— https://code.claude.com/docs/en/plugins-reference

Composing the two — the hook is live "when plugin is enabled", and enablement lives in the settings
file the install scope selects — and then confirming it empirically:

| Install scope | Settings file holding `enabledPlugins` | Where the hook fires | Evidence tier |
|---|---|---|---|
| `user` (**CLI default**) | `~/.claude/settings.json` | **Every project on the machine** | **Spike-observed** (Phase 1, 3 projects) |
| `project` | `<project>/.claude/settings.json` | That project only (committable) | **Spike-observed** (Phase 2, A blocked / B not) |
| `local` | `<project>/.claude/settings.local.json` | That project only (gitignored) | Doc-only — not exercised by the spike |
| `managed` | Managed settings | Org-controlled, read-only / update-only | Doc-only — not exercised by the spike |

**Phase 1 — `claude plugin install kaba-spike@kaba-spike-market --scope user -y`.** Entry landed in
`~/.claude/settings.json`. With **no** `--plugin-dir` flag, the hook then blocked the write in **all
three** unrelated projects, including two that had no `.claude/` directory and had never heard of the
plugin:

```
spike-guard: blocked /private/tmp/kaba-test-a/SPIKE_BLOCKED.txt
spike-guard: blocked /private/tmp/kaba-test-b/SPIKE_BLOCKED.txt
spike-guard: blocked /private/tmp/kaba-test-c/SPIKE_BLOCKED.txt
```

`/tmp/kaba-test-c` is the "enabled but never initialized" case — no config of any kind — and the hook
still fired there.

**Phase 2 — uninstalled from `user`, reinstalled with `--scope project` from `/tmp/kaba-test-a`.**
The hook then fired in A and **not** in B:

- A: `spike-guard: blocked /private/tmp/kaba-test-a/SPIKE_BLOCKED.txt`, file not created.
- B: `Done — SPIKE_BLOCKED.txt was created … the write was not blocked.` (`-rw-r--r-- … 6 bytes`).

> ### Consequence for Task 6 — the fail-open guard is mandatory, not defensive polish
>
> `claude plugin install` defaults to **`--scope user`** (`-s, --scope <scope>  Installation scope:
> user, project, or local (default: "user")`). The realistic install is therefore user-global, and a
> user-global hook runs in **every project the user opens** — including projects that have never run
> `/kaba:init`. kaba's PreToolUse guard **must exit 0 immediately when `.kaba/config.yml` is absent**,
> or it will interfere with every non-kaba project on the machine. This is confirmed behaviour, not a
> theoretical risk.
>
> Related: kaba can't rely on `${CLAUDE_PROJECT_DIR}` being a kaba project. The guard should key off
> the presence of `.kaba/config.yml` in the project, and should also exit 0 when its own tooling is
> missing (the spike's `command -v jq >/dev/null 2>&1 || exit 0` line is the right pattern).

---

## Install & distribution mechanics (for Tasks 8 and 13)

### Local development — no install needed

```bash
claude --plugin-dir /path/to/kaba        # loads the plugin for that session only
claude --plugin-dir ./one --plugin-dir ./two   # repeatable
```

Verified: `claude -p "/kaba-spike:kaba.ping" --plugin-dir /tmp/kaba-spike` → `PONG`. Also accepts a
`.zip`; `--plugin-url` loads a hosted archive. A `--plugin-dir` plugin **overrides** an installed
plugin of the same name for that session (except managed force-enable/disable). `/reload-plugins`
picks up edits without restarting.

### Real install, via a marketplace

Marketplace catalog lives at `<marketplace-root>/.claude-plugin/marketplace.json`. Required top-level
fields: `name`, `owner` (with `owner.name`), `plugins`. Each plugin entry requires `name` and
`source`; it may carry any plugin-manifest field plus `category`, `tags`, `strict`, `relevance`.

The file the spike used, which passed `claude plugin validate`:

```json
{
  "name": "kaba-spike-market",
  "owner": {
    "name": "kaba spike"
  },
  "plugins": [
    {
      "name": "kaba-spike",
      "source": "./plugins/kaba-spike",
      "description": "Throwaway spike: verify manifest shape and hook self-registration",
      "version": "0.0.1"
    }
  ]
}
```

Commands, all run successfully:

```bash
claude plugin validate /path/to/kaba            # or the marketplace dir
claude plugin marketplace add /tmp/kaba-marketplace
claude plugin install kaba-spike@kaba-spike-market --scope user -y
claude plugin install kaba-spike@kaba-spike-market --scope project -y
claude plugin uninstall kaba-spike --scope user
claude plugin marketplace remove kaba-spike-market
claude plugin list          # version, source marketplace, scope, enabled status
claude plugin details <name>
claude plugin enable|disable <plugin> [-s <scope>]
```

`-y` is **required** when stdin/stdout is not a TTY. In-session equivalents are
`/plugin marketplace add ./dir` and `/plugin install <plugin>@<marketplace>`.

**Source types** for a plugin entry: relative path (string starting `./`, resolved from the
marketplace root — *not* from `.claude-plugin/`), or an object with `source:` `github` (`repo`,
`ref?`, `sha?`), `url`, `git-subdir`, `npm`, `archive`, `command`. `metadata.pluginRoot` can prefix
relative sources. Marketplace `name` is public-facing and globally unique per user — one marketplace
per name, and a set of Anthropic-official names is reserved.

**Install copies the plugin** into `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`.
Copied plugins **cannot** reference files outside their own directory (`../shared`) — everything kaba
ships must live inside the plugin directory.

---

## Surprises / caveats

1. **Namespacing is the whole answer to (c)** and it bites: `kaba.init.md` really would become
   `/kaba:kaba.init`. Renaming to `init.md` is required, not cosmetic.
2. **Install defaults to user scope**, which makes the user-global hook blast radius the *default*
   experience, not an edge case. This is the single most important input to Task 6.
3. **A dot in a command filename is fine** — `kaba.ping.md` registered cleanly as `kaba.ping`. The
   problem is purely the visual stutter against the plugin prefix.
4. **`commands/` is described as the older layout** ("Use `skills/` for new plugins") even though it
   works. Task 8 should make a deliberate choice; naming behaviour is identical either way.
5. **`commands/` subdirectories are not scanned** — kaba's command files must be flat.
6. `claude plugin validate` **warns** on a missing `author`. Ship one; `--strict` promotes it to an
   error and the community-marketplace pipeline runs the same check.
7. The blocking message surfaced to the model as
   `PreToolUse:Write hook error: [<command>]: <stderr>` — the guard's stderr is quoted verbatim, so
   kaba's guard messages are read by the agent exactly as written. Write them as instructions to the
   agent.
8. `claude plugin details` prices hooks as **"harness-only — no model context cost"**; the spike's one
   command cost ~30 always-on tokens. Per-command always-on cost is the budget to watch as kaba's
   command count grows.

---

## Frontmatter keys — verified 2026-08-17, CLI 2.1.233

Added while planning the F-1 overwrite gate. Both facts bear directly on the pending
`commands/` → `skills/` migration and were expensive to establish; do not re-derive them.

### `disable-model-invocation` works in `commands/*.md` — the migration is not what buys it

**Spike-observed.** The key lives in the frontmatter schema shared by both layouts, and Claude Code's
own command documentation covers it: `plugin-dev/skills/command-development/references/frontmatter-reference.md:270`
documents it under **command** frontmatter, with `---` examples carrying nothing but `description`
plus the flag. Its stated purpose, verbatim: *"Prevent SlashCommand tool from programmatically
invoking command"*, and when true: *"Command only invokable by user typing `/command` · Not available
to SlashCommand tool"*.

Corroborating, on this machine: Anthropic's own `cwc-makers/commands/maker-setup.md:3` sets
`disable-model-invocation: true` in a plain `commands/` file, and `plugin-dev`'s command-development
skill states *"The `.claude/commands/` directory is a legacy format… Both are loaded identically —
the only difference is file layout."* The 2.1.3 changelog entry is *"Merged slash commands and skills,
simplifying the mental model with no change in behavior"* — which is directly observable here, since
kaba ships only `commands/` yet its thirteen register as skills.

> **Consequence.** `docs/roadmap.md`'s claim that migrating to `skills/` is what buys
> `disable-model-invocation` is wrong. The flag can be added wherever the files currently live. The
> migration has to justify itself on the legacy-layout argument and on the skill-only frontmatter keys
> (`when_to_use`, `paths`, `hooks`, `context: inline|fork`, `agent`, `background`) instead.

**Not verified:** whether the flag also removes the description from model context. The documentation
describes invocation blocking only, and the binary carries a refusal string
(*"cannot be used with Skill tool due to disable-model-invocation"*) implying the model still sees the
skill and is refused at call time. Do not repeat the context-saving claim without testing it.

### `handoffs:` is a VS Code key and does nothing in Claude Code

**Spike-observed.** `handoffs` is absent from the frontmatter key list compiled into the CLI binary —
that list runs `…"disable-model-invocation","user-invocable","effort","shell","version","when_to_use","paths","hooks","context","agent",…`
— and the binary carries an `unknown frontmatter key "…" (expected one of: …)` diagnostic. The
lowercase string appears exactly once in the whole binary, inside an unrelated remote-control
heartbeat message; the capitalized occurrences are `WorkflowLaunchHandoffs` symbols from the Workflow
subsystem. The only `handoffs:` frontmatter anywhere on this machine is kaba's own nine command files.

It is a **VS Code custom-agents** feature. From VS Code's documentation: *"Handoffs enable you to
create guided sequential workflows that transition between agents with suggested next steps… After a
chat response completes, handoff buttons appear that let users move to the next agent with relevant
context and a pre-filled prompt."* The sub-properties match kaba's exactly — `label` is the button
text, `agent` the target, `prompt` the pre-filled text, `send` auto-submits (default `false`).

kaba inherited it from spec-kit, whose `templates/commands/*.md` are multi-target source templates
transformed per agent by the `specify` CLI. spec-kit's `AGENTS.md:447` has the Forge integration
*"Strips `handoffs` frontmatter key"*, and the changelog entry that introduced it reads *"Use VS Code
handoffs."* It was never a cross-agent convention.

> **Consequence.** There is no handoffs carryover to verify during the migration — the key is inert in
> `commands/` today. And the pipeline does not chain: only `specify.md`, `init.md`, and `fix-tests.md`
> name a next step in prose, so after the other ten finish, nothing tells the user or the agent what
> comes next. Deleting the nine blocks and replacing them with prose pointers is migration-pass work.
