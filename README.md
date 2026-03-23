# Telegram Per-Project

Connect a Telegram bot to your Claude Code with an MCP server. Per-project mode gives each project its own bot, access policy, and message inbox. Includes a `claude-bot` watchdog that monitors the session, sends Telegram notifications on exit, and auto-retries.

## Prerequisites

- [Bun](https://bun.sh) — the MCP server runs on Bun. Install with `curl -fsSL https://bun.sh/install | bash`.
- `curl` — used by `claude-bot` for Telegram API calls (pre-installed on most systems).

## Installation

Clone the repo and run the installer:

```bash
git clone https://github.com/trezero/telegram-per-project.git
cd telegram-per-project
./install.sh
```

This does two things:
1. Symlinks `claude-bot` to `~/.local/bin` (or `~/bin`) so it's available globally
2. Installs the `telegram@claude-plugins-official` plugin for Claude Code

You can specify a custom install directory: `./install.sh /usr/local/bin`

Since it's a symlink, `git pull` updates take effect immediately — no re-install needed.

## Quick Setup

> Default pairing flow for a single-user DM bot. See [ACCESS.md](./ACCESS.md) for groups and multi-user setups.

**1. Create a bot with BotFather.**

Open a chat with [@BotFather](https://t.me/BotFather) on Telegram and send `/newbot`. BotFather asks for two things:

- **Name** — the display name shown in chat headers (anything, can contain spaces)
- **Username** — a unique handle ending in `bot` (e.g. `my_assistant_bot`). This becomes your bot's link: `t.me/my_assistant_bot`.

BotFather replies with a token that looks like `123456789:AAHfiqksKZ8...` — that's the whole token, copy it including the leading number and colon.

**2. Install the plugin.**

These are Claude Code commands — run `claude` to start a session first.

Install the plugin:
```
/plugin install telegram@claude-plugins-official
```

**3. Configure and launch.**

The easiest way is to run `claude-bot` in your project directory — it detects missing config and walks you through setup interactively:

```bash
cd ~/projects/myproject
claude-bot
```

It will prompt for a project ID and bot token, validate the token with Telegram, write all config files, and launch the session.

Alternatively, configure manually with the skill:

```
/telegram:configure 123456789:AAHfiqksKZ8...
```

Then launch with:

```sh
claude-bot
# or without the watchdog:
claude --channels plugin:telegram@claude-plugins-official
```

**4. Pair.**

DM your bot on Telegram — it replies with a 6-character pairing code. In your Claude Code session:

```
/telegram:access pair <code>
```

Your next DM reaches the assistant.

> Unlike Discord, there's no server invite step — Telegram bots accept DMs immediately. Pairing handles the user-ID lookup so you never touch numeric IDs.

**5. Lock it down.**

Pairing is for capturing IDs. Once you're in, switch to `allowlist` so strangers don't get pairing-code replies. Ask Claude to do it, or `/telegram:access policy allowlist` directly.

## `claude-bot` — Session Launcher & Watchdog

`claude-bot` wraps Claude Code with process monitoring, Telegram notifications, and automatic retries. It's the recommended way to run long-lived sessions.

```
Usage: claude-bot [options] [project-dir]

Options:
  -dsp          Add --dangerously-skip-permissions to the claude command
  --retries N   Max consecutive restart attempts (default: 3, 0 = no restart)
  --cooldown S  Seconds between restarts (default: 10)
  -h, --help    Show usage

Arguments:
  project-dir   Directory to run in (default: current directory)
```

### What it does

1. **Resolves project context** — reads `TELEGRAM_STATE_DIR` / `TELEGRAM_PROJECT_ID` from `.claude/settings.local.json` to find the bot token and access config
2. **Interactive setup** — if no Telegram config exists for the project, guides you through setup (project ID, bot token validation, config file creation)
3. **Launches Claude Code** with `--channels plugin:telegram@claude-plugins-official` in the foreground
4. **Notifies on exit** — sends a Telegram message to all `allowFrom` users when the session ends
5. **Retries with backoff** — waits `--cooldown` seconds and relaunches (up to `--retries` times)
6. **Stability heuristic** — if a session ran for >5 minutes, the retry counter resets (distinguishes auth expiry from crash loops)
7. **Clean shutdown** — `Ctrl+C` / `SIGTERM` forwards to Claude Code and suppresses the "session died" notification

### Examples

```bash
# Basic usage — run in current project directory
claude-bot

# With skip-permissions flag
claude-bot -dsp

# Explicit project directory, no retries
claude-bot --retries 0 ~/projects/myproject

# In tmux for persistence
tmux new -s myproject "claude-bot -dsp ~/projects/myproject"
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

Both variables are passed via the `env` block in `.claude/settings.local.json` in your project root. The `claude-bot` interactive setup and `/telegram:configure --project` command write this automatically, but the resulting structure is:

```json
{
  "env": {
    "TELEGRAM_PROJECT_ID": "myproject",
    "TELEGRAM_STATE_DIR": "/home/you/.claude/channels/telegram/projects/myproject"
  }
}
```

**Note:** The installed plugin from `claude-plugins-official` reads `TELEGRAM_STATE_DIR`. Setting both ensures compatibility whether the session runs the installed plugin or a local development copy of the server.

Claude Code's `env` is a flat `Record<string, string>` — all values must be strings, no nesting. These environment variables are passed to all MCP server processes at startup.

**Important:** The `env` block does **not** support nested structures like `env.mcpServers.telegram`. Both variables must be direct keys in the `env` object.

### Project ID rules

- Allowed characters: letters, digits, hyphens, underscores (`[a-zA-Z0-9_-]`)
- Maximum length: 64 characters
- Used as a directory name — path separators (`/`, `\`, `..`) are rejected
- Validated both by the configure skill and by `server.ts` at startup (fail-fast on invalid IDs)

### Setup walkthrough

The fastest path is to run `claude-bot` in each project directory — it handles everything interactively. For manual setup:

**1. Create a bot per project** with [@BotFather](https://t.me/BotFather). Give each a descriptive username (e.g. `@myproject_dev_bot`).

**2. Configure each project.** In the project's Claude Code session:

```
/telegram:configure --project myproject 123456789:AAH...
```

This does four things:
1. Creates `~/.claude/channels/telegram/projects/myproject/`
2. Saves the bot token to `projects/myproject/.env` (mode `0600`)
3. Writes `TELEGRAM_PROJECT_ID=myproject` to the project's `.claude/settings.local.json`
4. Copies `allowFrom` from the global `access.json` as the initial per-project access list (if the global config exists)

**3. Launch** with `claude-bot` or manually:

```sh
# Recommended — with watchdog and notifications:
cd ~/projects/myproject && claude-bot

# Or manually:
cd ~/projects/myproject && claude --channels plugin:telegram@claude-plugins-official
```

**4. Pair** by DMing the project's bot. If your user ID was already in the global allowlist, it carries over automatically and you can skip pairing. Otherwise, the bot replies with a pairing code — approve with `/telegram:access pair <code>` as usual.

**5. Run multiple sessions** — each project directory launches its own bot:

```sh
# Terminal 1: Alpha project connects to @alpha_dev_bot
cd ~/projects/alpha && claude-bot

# Terminal 2: Beta project connects to @beta_dev_bot
cd ~/projects/beta && claude-bot

# Terminal 3: No project ID — connects to the global bot
cd ~/projects/other && claude-bot
```

DM `@alpha_dev_bot` to reach Terminal 1, `@beta_dev_bot` to reach Terminal 2. Messages never cross between sessions.

### Access inheritance

When a per-project `access.json` is created for the first time (either by `claude-bot` setup, the configure skill, or the server's startup bootstrap), it inherits the `allowFrom` list from the global `~/.claude/channels/telegram/access.json`. After creation, the per-project config is fully independent — changes to the global config do not propagate, and vice versa.

### Verifying your setup

Check which mode a project is using:

```
/telegram:configure
```

This shows the active mode (global or per-project), the resolved state directory, token status, and access summary.

### Removing per-project configuration

```
/telegram:configure clear
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
