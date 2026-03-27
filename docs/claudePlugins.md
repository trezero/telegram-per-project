# Claude Code Plugins: Architecture, Lessons, and Roadmap

This document captures everything learned while building the `telegram-per-project` plugin,
including how the Claude Code plugin system works, what broke during our first deployment,
the beta workflow we adopted, and what's needed to ship as a standalone marketplace plugin.

---

## Table of Contents

1. [How Claude Code Plugins Work](#how-claude-code-plugins-work)
2. [Plugin Directory Structure](#plugin-directory-structure)
3. [Key Plugin Concepts](#key-plugin-concepts)
4. [The --channels Flag and Channel Plugins](#the---channels-flag-and-channel-plugins)
5. [Current State of Our Plugin](#current-state-of-our-plugin)
6. [Beta Workflow (Current)](#beta-workflow-current)
7. [Bugs and Lessons Learned](#bugs-and-lessons-learned)
8. [Roadmap: Publishing to Our Own Marketplace](#roadmap-publishing-to-our-own-marketplace)
9. [Reference Links](#reference-links)

---

## How Claude Code Plugins Work

### What is a plugin?

A plugin is a self-contained directory that extends Claude Code with custom functionality.
Plugins can contain any combination of:

- **Skills** (`skills/`) — prompt templates invoked by `/plugin-name:skill-name`
- **Commands** (`commands/`) — simpler skill files (legacy, prefer `skills/`)
- **Agents** (`agents/`) — specialized subagents for specific tasks
- **Hooks** (`hooks/hooks.json`) — event handlers that run shell commands on lifecycle events
- **MCP servers** (`.mcp.json`) — Model Context Protocol servers providing tools
- **LSP servers** (`.lsp.json`) — Language Server Protocol for code intelligence
- **Settings** (`settings.json`) — default config applied when the plugin is enabled

### Plugin vs standalone

| Approach | Skill names | Best for |
|----------|-------------|----------|
| **Standalone** (`.claude/` directory) | `/hello` | Personal workflows, single-project |
| **Plugin** (`.claude-plugin/plugin.json`) | `/plugin-name:hello` | Sharing, distribution, reuse |

Plugin skills are always namespaced to prevent conflicts between plugins.

### How plugins are loaded

Two mechanisms:

1. **Marketplace install** — `claude plugin install name@marketplace`
   - Plugin is copied to `~/.claude/plugins/cache/<marketplace>/<name>/<version>/`
   - Also appears in `~/.claude/plugins/marketplaces/<marketplace>/external_plugins/<name>/`
   - Claude loads from `external_plugins/` at runtime (not the versioned cache)
   - Persists across sessions

2. **`--plugin-dir <path>`** — loads from a local directory for one session
   - If same name as an installed plugin, the local copy takes precedence
   - Great for development: edit files, run `/reload-plugins` to pick up changes
   - Does NOT persist — must be passed every time

### How plugins are installed permanently

`claude plugin install` only accepts marketplace identifiers:
```bash
# Works:
claude plugin install telegram@claude-plugins-official

# Does NOT work:
claude plugin install /local/path/to/plugin
claude plugin install trezero/telegram-per-project
```

Local path installs fail with: `Plugin "..." not found in any configured marketplace`.

To install a custom plugin permanently, you must create a marketplace (see [Roadmap](#roadmap-publishing-to-our-own-marketplace)).

---

## Plugin Directory Structure

### Standard layout

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json          # Manifest (name, version, channels, mcpServers, etc.)
├── skills/
│   └── my-skill/
│       └── SKILL.md         # Skill definition with frontmatter
├── agents/
│   └── my-agent.md          # Agent definition with frontmatter
├── hooks/
│   └── hooks.json           # Event handlers
├── .mcp.json                # MCP server definitions
├── .lsp.json                # LSP server definitions
├── settings.json            # Default settings (only `agent` key supported)
├── scripts/                 # Hook and utility scripts
├── package.json             # Dependencies (if server needs them)
└── server.ts                # MCP server implementation
```

**Important:** Only `plugin.json` goes inside `.claude-plugin/`. Everything else goes at the plugin root.

### plugin.json schema (key fields)

```json
{
  "name": "plugin-name",           // Required. Used as skill namespace prefix.
  "version": "1.1.0",              // Semantic versioning. Must bump to trigger updates.
  "description": "...",            // Shown in plugin manager.
  "author": { "name": "..." },
  "repository": "https://...",
  "license": "MIT",
  "keywords": ["..."],

  "channels": [                    // Declares this plugin provides a channel
    {
      "server": "server-key",      // Must match a key in mcpServers
      "userConfig": {              // Prompted at plugin enable time
        "bot_token": {
          "description": "...",
          "sensitive": true        // Stored in system keychain
        }
      }
    }
  ],

  "mcpServers": {                  // Inline MCP server definitions
    "server-key": {
      "command": "bun",
      "args": ["server.ts"],
      "cwd": "${CLAUDE_PLUGIN_ROOT}",
      "env": {
        "NODE_PATH": "${CLAUDE_PLUGIN_DATA}/node_modules"
      }
    }
  }
}
```

### Environment variables available in plugins

| Variable | Purpose |
|----------|---------|
| `${CLAUDE_PLUGIN_ROOT}` | Absolute path to the plugin's installed directory. Changes on update. |
| `${CLAUDE_PLUGIN_DATA}` | Persistent directory for state/deps (`~/.claude/plugins/data/{id}/`). Survives updates. |
| `CLAUDE_PLUGIN_OPTION_<KEY>` | Values from `userConfig`, set as env vars for MCP/LSP servers and hooks. |

### Skill SKILL.md frontmatter

```yaml
---
name: skill-name
description: What this skill does and when to invoke it.
user-invocable: true           # Shows in /help, user can type /plugin:skill
allowed-tools:                 # Restrict which tools the skill can use
  - Read
  - Write
  - Bash(ls *)
  - Bash(mkdir *)
---

# Skill content (prompt instructions)

Arguments passed: `$ARGUMENTS`
```

### SessionStart hook for dependency management

The official pattern for installing dependencies once and re-installing only when
`package.json` changes:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "diff -q \"${CLAUDE_PLUGIN_ROOT}/package.json\" \"${CLAUDE_PLUGIN_DATA}/package.json\" >/dev/null 2>&1 || (cd \"${CLAUDE_PLUGIN_DATA}\" && cp \"${CLAUDE_PLUGIN_ROOT}/package.json\" \"${CLAUDE_PLUGIN_ROOT}/bun.lock\" . && bun install --no-summary) || rm -f \"${CLAUDE_PLUGIN_DATA}/package.json\""
          }
        ]
      }
    ]
  }
}
```

The `diff` exits nonzero when the stored copy is missing or differs, covering both first run
and dependency-changing updates. If install fails, the trailing `rm` removes the copied
manifest so the next session retries.

---

## Key Plugin Concepts

### Plugin caching

Marketplace plugins are copied to `~/.claude/plugins/cache/` — they don't run from the
marketplace directory. Path traversal outside the plugin root doesn't work after installation.
Symlinks within the plugin directory are resolved during the copy.

### Two directories for marketplace plugins

Claude Code keeps marketplace plugins in TWO locations:

| Location | Purpose |
|----------|---------|
| `~/.claude/plugins/cache/<marketplace>/<name>/<version>/` | Versioned copy |
| `~/.claude/plugins/marketplaces/<marketplace>/external_plugins/<name>/` | **Runtime copy** (what Claude actually loads) |

This matters when patching skills — you must patch `external_plugins/`, not just the cache.
Plugin updates overwrite both directories.

### userConfig and sensitive values

`userConfig` fields are prompted when the plugin is enabled. Values marked `sensitive: true`
go to the system keychain (or `~/.claude/.credentials.json` as fallback). There is an
approximately 2KB total limit for keychain storage across all plugins.

Non-sensitive values are stored in `settings.json` under `pluginConfigs[<plugin-id>].options`.

All values are exported as `CLAUDE_PLUGIN_OPTION_<KEY>` environment variables to plugin
subprocesses.

### Plugin installation scopes

| Scope | Settings file | Use case |
|-------|---------------|----------|
| `user` | `~/.claude/settings.json` | Personal, all projects (default) |
| `project` | `.claude/settings.json` | Shared via version control |
| `local` | `.claude/settings.local.json` | Project-specific, gitignored |

---

## The --channels Flag and Channel Plugins

### What --channels does

The `--channels` flag tells Claude Code to listen for inbound messages from a channel
(Telegram, Slack, Discord, etc.) and inject them into the conversation. Without it, the
MCP server may run, but messages are not pushed into the session.

### Format requirements

```
--channels plugin:<name>@<marketplace>    # Plugin-provided channel
--channels server:<name>                  # Manually configured MCP server
```

**`plugin:<name>` (without @marketplace) is INVALID** and will be rejected:

```
--channels entries must be tagged: plugin:telegram-per-project
  plugin:<name>@<marketplace>  — plugin-provided channel (allowlist enforced)
  server:<name>                — manually configured MCP server
```

### Why this matters for development

- A plugin loaded via `--plugin-dir` is NOT tied to any marketplace
- Therefore it cannot be referenced in `--channels plugin:...` format
- The channel must come from a marketplace-installed plugin
- `--plugin-dir` can only add/override skills, agents, and hooks — not provide the channel itself

### The beta workaround

Use the official marketplace plugin for the channel transport, and `--plugin-dir` for
skill/hook overrides:

```bash
claude \
  --channels plugin:telegram@claude-plugins-official \
  --plugin-dir /path/to/telegram-per-project
```

The official plugin owns the MCP wiring (transport). Our local plugin owns the logic
(skills, hooks, agents).

---

## Current State of Our Plugin

### What we have (v1.1.0)

| Component | File | Status |
|-----------|------|--------|
| Plugin manifest | `.claude-plugin/plugin.json` | Has `channels`, `userConfig`, `mcpServers` |
| MCP server | `server.ts` | Telegram bot + MCP tools (reply, react, edit_message) |
| MCP config | `.mcp.json` | Uses `${CLAUDE_PLUGIN_ROOT}` and `${CLAUDE_PLUGIN_DATA}` |
| Access skill | `skills/access/SKILL.md` | Per-project state dir resolution |
| Configure skill | `skills/configure/SKILL.md` | Per-project state dir resolution |
| Dependency hook | `hooks/hooks.json` | SessionStart with `${CLAUDE_PLUGIN_DATA}` pattern |
| Watchdog | `claude-gram` | Session launcher with retry, notifications, `--plugin-dir` support |
| Installer | `install.sh` | Copies claude-gram, installs bun |
| Uninstaller | `uninstall.sh` | Cleanup with `--purge` and `--project` options |

### Bot token resolution (server.ts)

Priority order:
1. `CLAUDE_PLUGIN_OPTION_bot_token` — from plugin `userConfig` (keychain-backed)
2. `TELEGRAM_BOT_TOKEN` — from `settings.local.json` env block or shell environment
3. `.env` file in state directory — legacy fallback

### State directory resolution (server.ts + skills)

Priority order:
1. `TELEGRAM_STATE_DIR` env var — full path override
2. `TELEGRAM_PROJECT_ID` env var — builds `~/.claude/channels/telegram/projects/<id>/`
3. Neither set — falls back to `~/.claude/channels/telegram/` (global)

### What the official marketplace plugin provides

The `telegram@claude-plugins-official` plugin provides:
- The MCP channel server (Telegram bot polling, message injection)
- Skills (`/telegram:access`, `/telegram:configure`) — but these hardcode the global
  state path and lack per-project support
- The `--channels` identity (`plugin:telegram@claude-plugins-official`)

### What our local plugin adds/overrides

When loaded via `--plugin-dir`:
- Skills with per-project state directory resolution (overrides marketplace skills)
- `hooks/hooks.json` with SessionStart dependency management
- `userConfig` for bot token (keychain storage)

### What claude-gram does

1. Reads project context from `.claude/settings.local.json`
2. Runs interactive setup if no Telegram config exists
3. Launches `claude --channels plugin:telegram@claude-plugins-official [--plugin-dir ...] [--dangerously-skip-permissions]`
4. Monitors process, notifies `allowFrom` users on exit via Telegram API
5. Retries with configurable backoff (resets after 5 minutes of stability)

---

## Beta Workflow (Current)

### Prerequisites

1. `bun` installed (the installer handles this)
2. `telegram@claude-plugins-official` marketplace plugin installed
3. This repo cloned locally

### Per-machine setup

```bash
git clone https://github.com/trezero/telegram-per-project.git
cd telegram-per-project
./install.sh
```

### Per-project setup

```bash
cd ~/projects/myproject
claude-gram --plugin-dir ~/projects/telegram-per-project
```

First run triggers interactive setup: project ID, bot token, config file creation.

### Running sessions

```bash
# With plugin overrides (recommended during development)
claude-gram -dsp --plugin-dir ~/projects/telegram-per-project

# Without plugin overrides (marketplace skills only)
claude-gram -dsp
```

### Pairing flow

1. DM the bot on Telegram — it replies with a 6-character code
2. In the Claude session: `/telegram-per-project:access pair <code>`
   (or `/telegram:access pair <code>` if not using `--plugin-dir`)
3. Lock down: `/telegram-per-project:access policy allowlist`

---

## Bugs and Lessons Learned

### Issue 1: GNU sed range injected env inside hooks

**Root cause:** `interactive_setup()` in `claude-gram` used `sed '1,/{/'` to add the `env`
block after the opening brace of `settings.local.json`. GNU sed extends the `1,/regex/`
range to the SECOND line matching the regex (since line 1 itself matches `{`, it looks for
the next `{`). If the file has `"hooks": {` on line 2, the env block gets appended inside
hooks.

**Fix:** Changed to `sed '1a\...'` which appends strictly after line 1.

**Lesson:** GNU sed address ranges behave differently than expected when line 1 matches the
closing pattern. Always test sed commands against files with nested braces.

### Issue 2: --channels flag silently ignored (pre-v2.1.84)

**Root cause:** Earlier testing suggested `--channels` didn't exist. It actually does work
but is undocumented in `--help`. It was being silently accepted but the plugin wasn't loading
because bun wasn't installed.

**Lesson:** Multiple failures can mask each other. The channel flag was fine; the runtime was
missing.

### Issue 3: bun not installed

**Root cause:** The Telegram plugin's `server.ts` requires bun (`#!/usr/bin/env bun`). Without
bun on PATH, the MCP server fails silently — the bot never polls Telegram.

**Fix:** `install.sh` now installs bun if missing and symlinks it into `~/.local/bin/`.

**Lesson:** Plugin dependencies should be documented and the installer should verify them.
The `SessionStart` hook pattern with `${CLAUDE_PLUGIN_DATA}` is the official way to handle this.

### Issue 4: Circular bun symlink

**Root cause:** `install.sh` found bun at `~/.local/bin/bun` (from a previous install) and
tried to create `~/.local/bin/bun -> ~/.local/bin/bun`. This broke bun entirely:
`Too many levels of symbolic links`.

**Fix:** Use `readlink -f` to resolve both paths before comparing. Skip symlink creation if
source and target resolve to the same file.

### Issue 5: Skills loaded from external_plugins, not cache

**Root cause:** When patching marketplace plugin skills, we patched
`~/.claude/plugins/cache/.../telegram/0.0.4/skills/` but Claude loads from
`~/.claude/plugins/marketplaces/.../external_plugins/telegram/skills/`. Both directories
must be patched, or the old skills are used.

**Fix:** Patch both directories. Better fix: use `--plugin-dir` which completely overrides
the marketplace skills for the session.

**Lesson:** Claude Code has TWO copies of marketplace plugins. The `external_plugins/`
directory is what's actually loaded at runtime.

### Issue 6: `claude plugin install /local/path` doesn't work

**Root cause:** The plugin install command only accepts `name@marketplace` identifiers.
Local paths, GitHub user/repo references, and bare names are all rejected.

**Fix:** Use `--plugin-dir` for development. For permanent installation, create a marketplace.

### Issue 7: --channels requires @marketplace suffix

**Root cause:** `--channels plugin:telegram-per-project` is invalid. The format must be
`plugin:<name>@<marketplace>`. A plugin loaded via `--plugin-dir` cannot be used as a
channel source.

**Fix:** Keep using `plugin:telegram@claude-plugins-official` for the channel. Use
`--plugin-dir` only for skill/hook overrides.

---

## Roadmap: Publishing to Our Own Marketplace

### Step 1: Create the plugin repository

A dedicated repo for the publishable plugin (e.g. `pixit-media/telegram-per-project-plugin`).

This contains the full plugin: `.claude-plugin/plugin.json`, `server.ts`, `skills/`, `hooks/`,
`.mcp.json`, `package.json`.

### Step 2: Create the marketplace repository

A separate repo that indexes plugins (e.g. `pixit-media/claude-marketplace`).

Create `marketplace.json`:

```json
{
  "name": "pixit-tools",
  "owner": {
    "name": "Pixit Media AI+",
    "email": "ai@pixitmedia.com"
  },
  "plugins": [
    {
      "name": "telegram-per-project",
      "source": {
        "source": "github",
        "repo": "pixit-media/telegram-per-project-plugin",
        "ref": "main"
      },
      "description": "Per-project Telegram channels for Claude Code sessions",
      "version": "1.1.0",
      "author": {
        "name": "Pixit Media AI+"
      }
    }
  ]
}
```

The `source.repo` points to the plugin repo; the marketplace just indexes it.

### Step 3: Register the marketplace

From a Claude Code session:

```
/plugin marketplace add pixit-media/claude-marketplace
```

Or add to managed settings for team-wide distribution:

```json
{
  "extraKnownMarketplaces": [
    { "source": "github", "repo": "pixit-media/claude-marketplace" }
  ]
}
```

### Step 4: Install and test

```bash
claude plugin install telegram-per-project@pixit-tools
```

Verify:
- Plugin appears in `/plugin list`
- MCP server starts (check for `telegram channel: polling as @...` in stderr)
- Skills are namespaced as `/telegram-per-project:access` etc.
- Channel messages flow without `--plugin-dir`

### Step 5: Update claude-gram

Once installed from our marketplace:

```bash
# Before (beta):
CLAUDE_CMD=(claude --channels plugin:telegram@claude-plugins-official)

# After (production):
CLAUDE_CMD=(claude --channels plugin:telegram-per-project@pixit-tools)
```

At this point, `--plugin-dir` is only needed for bleeding-edge development.

### Step 6 (optional): Stable vs latest channels

Create two marketplace entries pointing at different git refs:

| Marketplace | Ref | Audience |
|-------------|-----|----------|
| `pixit-tools-stable` | `stable` branch | Production users |
| `pixit-tools-latest` | `main` branch | Developers / early adopters |

Use managed settings to control who sees which:

```json
{
  "extraKnownMarketplaces": [
    { "source": "github", "repo": "pixit-media/claude-marketplace", "ref": "stable" }
  ]
}
```

### Checklist before publishing

- [ ] Plugin loads cleanly via `--plugin-dir` with no errors
- [ ] All skills resolve per-project state directories correctly
- [ ] SessionStart hook installs dependencies without errors
- [ ] Bot token resolution works via all three methods
- [ ] Pairing flow works end-to-end on a fresh machine
- [ ] `install.sh` works on a clean machine (no pre-existing bun/config)
- [ ] `uninstall.sh --purge` removes everything cleanly
- [ ] Version bumped in both `plugin.json` and `package.json`
- [ ] README updated with marketplace install instructions
- [ ] Plugin repo is public (or accessible to all intended users)
- [ ] Marketplace repo is public (or added to managed settings)

---

## Reference Links

- [Claude Code Plugins Overview](https://code.claude.com/docs/en/plugins) — creating plugins, skills, hooks, MCP integration
- [Claude Code Plugins Reference](https://code.claude.com/docs/en/plugins-reference) — full schema, CLI commands, debugging
- [Claude Code Overview](https://code.claude.com/docs/en/overview) — how plugins fit into the agentic workflow
- [Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces) — creating and distributing marketplaces
- [Skills Reference](https://code.claude.com/docs/en/skills) — skill authoring, frontmatter, arguments
- [Hooks Reference](https://code.claude.com/docs/en/hooks) — event handlers, lifecycle events
- [MCP Reference](https://code.claude.com/docs/en/mcp) — Model Context Protocol integration
