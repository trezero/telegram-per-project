# `claude-gram` — Session Launcher & Watchdog

**Date:** 2026-03-23
**Status:** Design approved
**Branch:** To be implemented on a separate feature branch off `main`

## Problem

Claude Code sessions on Max plans use OAuth tokens that expire roughly every 12 hours.
When a session dies (auth expiry, crash, or manual exit), the Telegram MCP server dies
with it — the bot stops polling and Telegram messages go into a void. The user has no
notification that their bot is offline, and must manually restart.

## Solution

A self-contained bash script (`claude-gram`) that:
1. Launches Claude Code with `--channels plugin:telegram@claude-plugins-official`
2. Monitors the process for exit
3. Sends a Telegram notification when the session ends
4. Optionally retries a configurable number of times before giving up

No new dependencies — uses `curl` for Telegram API calls and `jq`-free JSON parsing.

## Interface

```
Usage: claude-gram [options] [project-dir]

Options:
  -dsp          Add --dangerously-skip-permissions to the claude command
  --retries N   Max consecutive restart attempts (default: 3, 0 = no restart)
  --cooldown S  Seconds between restarts (default: 10)
  -h, --help    Show usage

Arguments:
  project-dir   Directory to run in (default: current directory)
```

### Examples

```bash
# Basic usage — run in current project directory
claude-gram

# With skip-permissions flag
claude-gram -dsp

# Explicit project directory, no retries
claude-gram --retries 0 ~/projects/archon

# In tmux for persistence
tmux new -s archon "claude-gram -dsp ~/projects/archon"
```

## Behavior

### 1. Resolve project context

On startup, the script determines which bot token to use for notifications:

1. Read `<project-dir>/.claude/settings.local.json`
2. Extract `TELEGRAM_PROJECT_ID` from the `env` object (flat `Record<string, string>`)
3. If found: bot token is at `~/.claude/channels/telegram/projects/<id>/.env`
4. If not found: bot token is at `~/.claude/channels/telegram/.env`
5. Also read `allowFrom` from the corresponding `access.json` to determine who to notify

### 2. Validate

Before launching, verify:
- The project directory exists
- The bot token file exists and is readable
- `claude` is on PATH
- At least one user in `allowFrom` to notify

Exit with a clear error message if any check fails.

### 3. Launch

```bash
cd "$project_dir"
claude --channels plugin:telegram@claude-plugins-official [--dangerously-skip-permissions]
```

The script `exec`s into Claude Code in the foreground — the user sees the normal
Claude Code UI and can interact with it. The script regains control only when
Claude Code exits.

### 4. On exit — notify

When Claude Code exits (any reason), the script sends a Telegram message to all
users in `allowFrom` via the bot's HTTP API:

```
curl -s "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -d chat_id="$user_id" \
  -d text="Claude Code session has ended (exit code: $code). To restart, run:

claude-gram [-dsp] $project_dir"
```

### 5. Retry logic

- If `--retries` > 0 and retries remain: wait `--cooldown` seconds, relaunch
- **Stability heuristic**: if a session ran for >5 minutes before dying, reset the
  retry counter (it was a real session, not a crash loop)
- If retries exhausted: send a final message:

  > "Session failed to restart after N attempts. Please re-authenticate
  > (`/login`) and run `claude-gram` again."

### 6. Clean exit

On `SIGINT`/`SIGTERM`, forward the signal to the Claude Code process and exit
cleanly without sending a "session died" notification (user intentionally stopped it).

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Language | Bash | Zero dependencies, works everywhere Claude Code runs |
| Notification transport | Direct Telegram HTTP API via curl | Reuses the bot token already on disk, no MCP server needed |
| Notification recipients | All users in `allowFrom` | They're the people who message this bot |
| Foreground execution | Yes (no daemonization) | User needs interactive access for `/login`, pairing, etc. |
| Signal handling | Forward SIGINT/SIGTERM, suppress notification | Clean exit shouldn't trigger "session died" alerts |
| Retry counter reset | After 5 minutes of uptime | Distinguishes auth expiry from crash loops |

## File Location

```
./claude-gram
```

Single file, `chmod +x`, no installation step. Users run it directly or symlink
to a directory on PATH.

## Out of Scope

- Daemonization / systemd units (use tmux/screen instead)
- Automatic `/login` (requires browser-based OAuth flow)
- Log rotation or PID files
- Decoupled bot architecture (bot running independently of Claude Code)

## Testing

Manual testing:

1. **Normal exit**: Start `claude-gram`, type `/exit` in Claude Code, verify Telegram notification
2. **Auth expiry simulation**: Start session, wait for token expiry, verify notification + retry
3. **Crash recovery**: Kill the claude process (`kill -9`), verify retry + notification
4. **Clean shutdown**: `Ctrl+C` the wrapper, verify NO notification sent
5. **Retries exhausted**: Set `--retries 1`, kill twice, verify final "re-authenticate" message
6. **Per-project**: Run in a project with `TELEGRAM_PROJECT_ID`, verify correct bot token used
7. **Global**: Run in a directory without project config, verify global bot token used
8. **-dsp flag**: Verify `--dangerously-skip-permissions` is passed through
