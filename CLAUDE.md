# CLAUDE.md — telegram-per-project

## What this project is

A Claude Code channel plugin that connects Telegram bots to Claude Code sessions with
per-project isolation. Each project gets its own bot, access policy, and message inbox.

## Key documentation

**Always read `docs/claudePlugins.md` before making changes to plugin configuration,
install scripts, or the channel setup.** It documents how the Claude Code plugin system
works, what broke during initial deployment, the current beta workflow, and the roadmap
for publishing to our own marketplace.

## Current architecture (beta)

The plugin operates in a split mode during beta:

- **Channel transport**: provided by the marketplace plugin `telegram@claude-plugins-official`
  (loaded via `--channels plugin:telegram@claude-plugins-official`)
- **Skills, hooks, agents**: provided by this local plugin
  (loaded via `--plugin-dir /path/to/this/repo`)

This split exists because `--channels` requires `plugin:<name>@<marketplace>` format and
we haven't published to our own marketplace yet. See `docs/claudePlugins.md` section
"The --channels Flag and Channel Plugins" for full explanation.

## Build and run

```bash
# Install (copies claude-gram to ~/.local/bin, installs bun)
./install.sh

# Run in a project directory
cd ~/projects/some-project
claude-gram -dsp --plugin-dir /path/to/telegram-per-project
```

## File overview

| File | Purpose |
|------|---------|
| `server.ts` | Telegram bot + MCP server (bun). Reads token, polls Telegram, delivers messages to Claude. |
| `claude-gram` | Bash watchdog. Launches Claude with --channels, monitors process, retries, sends notifications. |
| `.claude-plugin/plugin.json` | Plugin manifest with channels, userConfig, mcpServers declarations. |
| `.mcp.json` | MCP server config using `${CLAUDE_PLUGIN_ROOT}` and `${CLAUDE_PLUGIN_DATA}`. |
| `hooks/hooks.json` | SessionStart hook for dependency install via `${CLAUDE_PLUGIN_DATA}` pattern. |
| `skills/access/SKILL.md` | `/telegram-per-project:access` — pairing, allowlists, DM/group policy. |
| `skills/configure/SKILL.md` | `/telegram-per-project:configure` — token setup, project config, status. |
| `install.sh` | Copies claude-gram to PATH, installs bun if missing. |
| `uninstall.sh` | Removes claude-gram, optionally purges state. |

## Critical conventions

- **`--channels` requires `@marketplace` suffix.** Never use bare `plugin:<name>`. See Issue 7 in docs.
- **GNU sed `1,/{/` is broken for JSON injection.** Always use `sed '1a\...'`. See Issue 1 in docs.
- **Two plugin directories exist for marketplace plugins.** `external_plugins/` is what Claude loads at runtime, not the versioned cache. See Issue 5 in docs.
- **`install.sh` copies claude-gram, not symlinks.** This separates production from development.
- **Bot token priority:** `CLAUDE_PLUGIN_OPTION_bot_token` > `TELEGRAM_BOT_TOKEN` env > `.env` file.
- **State dir priority:** `TELEGRAM_STATE_DIR` > `TELEGRAM_PROJECT_ID` > global fallback.

## Testing changes

After editing, re-deploy and test:

```bash
# Deploy updated claude-gram to PATH
cp claude-gram ~/.local/bin/claude-gram && chmod +x ~/.local/bin/claude-gram

# Test in a project
cd ~/projects/test-project
claude-gram -dsp --plugin-dir /path/to/telegram-per-project
```

For skill changes, use `/reload-plugins` in a running session instead of restarting.
