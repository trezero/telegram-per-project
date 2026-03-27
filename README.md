# Telegram Per-Project

Connect a Telegram bot to Claude Code via an MCP channel plugin. Per-project mode gives each project its own bot, access policy, and message inbox. Includes a `claude-gram` watchdog that monitors the session, sends Telegram notifications on exit, and auto-retries.

## Prerequisites

- [Bun](https://bun.sh) — the MCP server runs on Bun. The installer will set it up if missing.
- `curl` — used by `claude-gram` for Telegram API calls (pre-installed on most systems).

## Installation

Clone the repo and run the installer:

```bash
git clone https://github.com/trezero/telegram-per-project.git
cd telegram-per-project
./install.sh
```

This does two things:
1. Copies `claude-gram` to `~/.local/bin` (or `~/bin`) so it's available globally
2. Installs [Bun](https://bun.sh) if not already present (the plugin runtime)

The installed copy is independent of the repo — re-run `./install.sh` to deploy updates.

You can specify a custom install directory: `./install.sh /usr/local/bin`

### Loading the plugin

The plugin is loaded by Claude Code at session start. Choose one:

```bash
# Development — loads from the cloned repo (this session only)
claude --plugin-dir /path/to/telegram-per-project

# Marketplace — permanent install (when published)
claude plugin install telegram-per-project@<marketplace>
```

When loaded via `--plugin-dir`, the local copy takes precedence over any installed marketplace version with the same name.

## Quick Setup

> Default pairing flow for a single-user DM bot. See [ACCESS.md](./ACCESS.md) for groups and multi-user setups.

**1. Create a bot with BotFather.**

Open a chat with [@BotFather](https://t.me/BotFather) on Telegram and send `/newbot`. BotFather asks for two things:

- **Name** — the display name shown in chat headers (anything, can contain spaces)
- **Username** — a unique handle ending in `bot` (e.g. `my_assistant_bot`). This becomes your bot's link: `t.me/my_assistant_bot`.

BotFather replies with a token that looks like `123456789:AAHfiqksKZ8...` — that's the whole token, copy it including the leading number and colon.

**2. Load the plugin and provide the token.**

When you enable the plugin, Claude Code prompts for the bot token (stored securely in the system keychain). Alternatively, configure manually:

```
/telegram-per-project:configure 123456789:AAHfiqksKZ8...
```

**3. Launch.**

```bash
cd ~/projects/myproject
claude-gram
```

If no Telegram config exists for the project, `claude-gram` guides you through interactive setup (project ID, token validation, config file creation).

Or launch manually without the watchdog:

```bash
claude --channels plugin:telegram@claude-plugins-official --plugin-dir /path/to/telegram-per-project
```

**4. Pair.**

DM your bot on Telegram — it replies with a 6-character pairing code. In your Claude Code session:

```
/telegram-per-project:access pair <code>
```

Your next DM reaches the assistant.

> Unlike Discord, there's no server invite step — Telegram bots accept DMs immediately. Pairing handles the user-ID lookup so you never touch numeric IDs.

**5. Lock it down.**

Pairing is for capturing IDs. Once you're in, switch to `allowlist` so strangers don't get pairing-code replies:

```
/telegram-per-project:access policy allowlist
```

## Plugin Structure

This plugin follows the [Claude Code plugin conventions](https://code.claude.com/docs/en/plugins-reference):

```
telegram-per-project/
├── .claude-plugin/
│   └── plugin.json          # Manifest: channels, userConfig, mcpServers
├── skills/
│   ├── access/SKILL.md      # /telegram-per-project:access — pairing, allowlists, policies
│   └── configure/SKILL.md   # /telegram-per-project:configure — token setup, status
├── hooks/
│   └── hooks.json           # SessionStart: install deps via ${CLAUDE_PLUGIN_DATA}
├── .mcp.json                # MCP server config (telegram channel server)
├── server.ts                # Telegram bot + MCP server (bun)
├── package.json             # Dependencies: grammy, @modelcontextprotocol/sdk
├── claude-gram              # Session launcher & watchdog script
├── install.sh               # Installer (bun + claude-gram copy)
└── uninstall.sh             # Cleanup script
```

Key conventions used:
- **`channels`** in plugin.json — declares this as a channel plugin bound to the `telegram` MCP server
- **`userConfig`** with `sensitive: true` — bot token prompted at enable time, stored in system keychain
- **`${CLAUDE_PLUGIN_DATA}`** — persistent directory for `node_modules` that survives plugin updates
- **SessionStart hook** — installs dependencies once, re-installs only when `package.json` changes

### Bot token resolution

The server reads the bot token from the first available source:

1. `CLAUDE_PLUGIN_OPTION_bot_token` — set by plugin `userConfig` (keychain-backed)
2. `TELEGRAM_BOT_TOKEN` — set via `settings.local.json` env block or shell environment
3. `.env` file in the state directory — legacy fallback for existing installations

## `claude-gram` — Session Launcher & Watchdog

`claude-gram` wraps Claude Code with process monitoring, Telegram notifications, and automatic retries. It's the recommended way to run long-lived sessions.

```
Usage: claude-gram [options] [project-dir]

Options:
  -dsp              Add --dangerously-skip-permissions to the claude command
  --plugin-dir DIR  Load a local plugin directory (skills/hooks override)
  --retries N       Max consecutive restart attempts (default: 3, 0 = no restart)
  --cooldown S      Seconds between restarts (default: 10)
  -h, --help        Show usage

Arguments:
  project-dir   Directory to run in (default: current directory)
```

### What it does

1. **Resolves project context** — reads `TELEGRAM_STATE_DIR` / `TELEGRAM_PROJECT_ID` from `.claude/settings.local.json` to find the bot token and access config
2. **Interactive setup** — if no Telegram config exists for the project, guides you through setup (project ID, bot token validation, config file creation)
3. **Launches Claude Code** with `--channels plugin:telegram@claude-plugins-official`
4. **Notifies on exit** — sends a Telegram message to all `allowFrom` users when the session ends
5. **Retries with backoff** — waits `--cooldown` seconds and relaunches (up to `--retries` times)
6. **Stability heuristic** — if a session ran for >5 minutes, the retry counter resets (distinguishes auth expiry from crash loops)
7. **Clean shutdown** — `Ctrl+C` / `SIGTERM` forwards to Claude Code and suppresses the "session died" notification

### Examples

```bash
# Basic usage — run in current project directory
claude-gram

# With skip-permissions flag
claude-gram -dsp

# Explicit project directory, no retries
claude-gram --retries 0 ~/projects/myproject

# In tmux for persistence
tmux new -s myproject "claude-gram -dsp ~/projects/myproject"
```

## Access control

See **[ACCESS.md](./ACCESS.md)** for DM policies, groups, mention detection, delivery config, skill commands, and the `access.json` schema.

Quick reference: IDs are **numeric user IDs** (get yours from [@userinfobot](https://t.me/userinfobot)). Default policy is `pairing`. `ackReaction` only accepts Telegram's fixed emoji whitelist.

## Per-project bots

By default, all Claude Code sessions share one bot token and one access config (the "global" setup described above). Per-project mode gives each project its own Telegram bot, access policy, and message inbox — so messages to `@alpha_dev_bot` only arrive in the Alpha project session, never in Beta's.

### How it works

The MCP server resolves its state directory from environment variables in this order:

1. `TELEGRAM_STATE_DIR` — full path override (takes precedence)
2. `TELEGRAM_PROJECT_ID` — just the ID; the server builds `~/.claude/channels/telegram/projects/<id>/`
3. Neither set — falls back to the global `~/.claude/channels/telegram/`

| | Global (default) | Per-project |
| --- | --- | --- |
| State dir | `~/.claude/channels/telegram/` | `~/.claude/channels/telegram/projects/<id>/` |
| Bot token | Shared across all sessions | One token per project |
| Access policy | Shared `access.json` | Independent per-project `access.json` |
| Inbox | Shared | Separate per project |

Each project-scoped state directory contains the same files as the global one:

```
~/.claude/channels/telegram/projects/<id>/
├── .env              # TELEGRAM_BOT_TOKEN for this project's bot
├── access.json       # per-project access policy
├── inbox/            # downloaded photos
└── approved/         # pairing approval signals
```

### Setting the environment variables

Both variables are passed via the `env` block in `.claude/settings.local.json` in your project root. The `claude-gram` interactive setup and `/telegram-per-project:configure --project` command write this automatically, but the resulting structure is:

```json
{
  "env": {
    "TELEGRAM_PROJECT_ID": "myproject",
    "TELEGRAM_STATE_DIR": "/home/you/.claude/channels/telegram/projects/myproject"
  }
}
```

Claude Code's `env` is a flat `Record<string, string>` — all values must be strings, no nesting. These environment variables are passed to all MCP server processes at startup.

### Project ID rules

- Allowed characters: letters, digits, hyphens, underscores (`[a-zA-Z0-9_-]`)
- Maximum length: 64 characters
- Used as a directory name — path separators (`/`, `\`, `..`) are rejected
- Validated both by the configure skill and by `server.ts` at startup (fail-fast on invalid IDs)

### Setup walkthrough

The fastest path is to run `claude-gram` in each project directory — it handles everything interactively. For manual setup:

**1. Create a bot per project** with [@BotFather](https://t.me/BotFather). Give each a descriptive username (e.g. `@myproject_dev_bot`).

**2. Configure each project.** In the project's Claude Code session:

```
/telegram-per-project:configure --project myproject 123456789:AAH...
```

This does four things:
1. Creates `~/.claude/channels/telegram/projects/myproject/`
2. Saves the bot token to `projects/myproject/.env` (mode `0600`)
3. Writes `TELEGRAM_PROJECT_ID=myproject` to the project's `.claude/settings.local.json`
4. Copies `allowFrom` from the global `access.json` as the initial per-project access list (if the global config exists)

**3. Launch** with `claude-gram` or manually:

```bash
# Recommended — with watchdog and notifications:
cd ~/projects/myproject && claude-gram

# Or manually with --plugin-dir:
cd ~/projects/myproject && claude --channels plugin:telegram@claude-plugins-official --plugin-dir /path/to/telegram-per-project
```

**4. Pair** by DMing the project's bot. If your user ID was already in the global allowlist, it carries over automatically and you can skip pairing. Otherwise, the bot replies with a pairing code — approve with `/telegram-per-project:access pair <code>` as usual.

**5. Run multiple sessions** — each project directory launches its own bot:

```bash
# Terminal 1: Alpha project connects to @alpha_dev_bot
cd ~/projects/alpha && claude-gram

# Terminal 2: Beta project connects to @beta_dev_bot
cd ~/projects/beta && claude-gram

# Terminal 3: No project ID — connects to the global bot
cd ~/projects/other && claude-gram
```

DM `@alpha_dev_bot` to reach Terminal 1, `@beta_dev_bot` to reach Terminal 2. Messages never cross between sessions.

### Access inheritance

When a per-project `access.json` is created for the first time (either by `claude-gram` setup, the configure skill, or the server's startup bootstrap), it inherits the `allowFrom` list from the global `~/.claude/channels/telegram/access.json`. After creation, the per-project config is fully independent — changes to the global config do not propagate, and vice versa.

### Verifying your setup

Check which mode a project is using:

```
/telegram-per-project:configure
```

This shows the active mode (global or per-project), the resolved state directory, token status, and access summary.

### Removing per-project configuration

```
/telegram-per-project:configure clear
```

In per-project mode, this removes the token from the per-project `.env` and removes `TELEGRAM_PROJECT_ID` from `.claude/settings.local.json`. After restarting, the session falls back to the global bot.

See [ACCESS.md](./ACCESS.md) for the full per-project access control reference.

## Tools exposed to the assistant

| Tool | Purpose |
| --- | --- |
| `reply` | Send to a chat. Takes `chat_id` + `text`, optionally `reply_to` (message ID) for native threading and `files` (absolute paths) for attachments. Images (`.jpg`/`.png`/`.gif`/`.webp`) send as photos with inline preview; other types send as documents. Max 50MB each. Auto-chunks text; files send as separate messages after the text. Returns the sent message ID(s). |
| `react` | Add an emoji reaction to a message by ID. **Only Telegram's fixed whitelist** is accepted (👍 👎 ❤ 🔥 👀 etc). |
| `edit_message` | Edit a message the bot previously sent. Useful for "working…" → result progress updates. Only works on the bot's own messages. |

Inbound messages trigger a typing indicator automatically — Telegram shows
"botname is typing…" while the assistant works on a response.

## Photos

Inbound photos are downloaded to `~/.claude/channels/telegram/inbox/` (or the project-scoped inbox in per-project mode) and the
local path is included in the `<channel>` notification so the assistant can
`Read` it. Telegram compresses photos — if you need the original file, send it
as a document instead (long-press → Send as File).

## No history or search

Telegram's Bot API exposes **neither** message history nor search. The bot
only sees messages as they arrive — no `fetch_messages` tool exists. If the
assistant needs earlier context, it will ask you to paste or summarize.

This also means there's no `download_attachment` tool for historical messages
— photos are downloaded eagerly on arrival since there's no way to fetch them
later.

## Uninstalling

```bash
# Remove claude-gram and bun symlinks, keep state
./uninstall.sh

# Also purge all state (tokens, access lists, inboxes)
./uninstall.sh --purge

# Also clean a specific project's settings.local.json
./uninstall.sh --purge --project ~/projects/myproject
```
