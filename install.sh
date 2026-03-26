#!/usr/bin/env bash
set -euo pipefail

# install.sh — Install claude-gram and the Telegram plugin for Claude Code.
# Symlinks claude-gram to a directory on PATH, installs bun if needed,
# installs the plugin, and runs bun install for its dependencies.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_BOT="$SCRIPT_DIR/claude-gram"

die() { printf 'install: %s\n' "$1" >&2; exit 1; }

[[ -f "$CLAUDE_BOT" ]] || die "claude-gram not found at $CLAUDE_BOT"

# ── Pick install directory ───────────────────────────────────────────────────

# Prefer ~/.local/bin (XDG), fall back to ~/bin
if [[ -d "$HOME/.local/bin" ]]; then
  INSTALL_DIR="$HOME/.local/bin"
elif [[ -d "$HOME/bin" ]]; then
  INSTALL_DIR="$HOME/bin"
else
  INSTALL_DIR="$HOME/.local/bin"
  mkdir -p "$INSTALL_DIR"
fi

# Allow override
if [[ -n "${1:-}" ]]; then
  INSTALL_DIR="$1"
  mkdir -p "$INSTALL_DIR"
fi

LINK="$INSTALL_DIR/claude-gram"

# ── Install claude-gram ───────────────────────────────────────────────────────

if [[ -e "$LINK" ]] || [[ -L "$LINK" ]]; then
  printf 'Updating existing install at %s\n' "$LINK"
  rm -f "$LINK"
fi

ln -s "$CLAUDE_BOT" "$LINK"
printf 'Installed: %s -> %s\n' "$LINK" "$CLAUDE_BOT"

# ── Ensure bun is installed ──────────────────────────────────────────────────
#
# The Telegram plugin (server.ts) requires bun to run. Without it, the plugin
# silently fails to start — the bot never polls Telegram and pairing never works.

BUN_BIN=""

if command -v bun >/dev/null 2>&1; then
  BUN_BIN="$(command -v bun)"
  printf '\nbun already installed: %s (%s)\n' "$BUN_BIN" "$(bun --version)"
elif [[ -x "$HOME/.bun/bin/bun" ]]; then
  BUN_BIN="$HOME/.bun/bin/bun"
  printf '\nbun found at %s (%s)\n' "$BUN_BIN" "$("$BUN_BIN" --version)"
else
  printf '\nbun not found — installing...\n'
  if ! command -v curl >/dev/null 2>&1; then
    printf 'Warning: curl not found; cannot install bun automatically.\n'
    printf 'Install bun manually: https://bun.sh/docs/installation\n'
  else
    curl -fsSL https://bun.sh/install | bash
    if [[ -x "$HOME/.bun/bin/bun" ]]; then
      BUN_BIN="$HOME/.bun/bin/bun"
      printf 'bun installed: %s\n' "$("$BUN_BIN" --version)"
    else
      printf 'Warning: bun install script ran but bun not found at ~/.bun/bin/bun\n'
    fi
  fi
fi

# Symlink bun into INSTALL_DIR so it's on the same PATH that Claude Code uses.
# Claude spawns plugin servers using the shell PATH at the time it was launched.
# Without this symlink, bun may not be visible to the plugin even if installed.
# Skip if BUN_BIN is already inside INSTALL_DIR — that would create a self-loop.
if [[ -n "$BUN_BIN" ]] && [[ -d "$INSTALL_DIR" ]]; then
  BUN_LINK="$INSTALL_DIR/bun"
  REAL_BUN_BIN="$(readlink -f "$BUN_BIN" 2>/dev/null || printf '%s' "$BUN_BIN")"
  REAL_BUN_LINK="$(readlink -f "$BUN_LINK" 2>/dev/null || printf '%s' "$BUN_LINK")"
  if [[ "$REAL_BUN_BIN" != "$REAL_BUN_LINK" ]]; then
    ln -sf "$REAL_BUN_BIN" "$BUN_LINK"
    printf 'Symlinked: %s -> %s\n' "$BUN_LINK" "$REAL_BUN_BIN"
  else
    printf 'bun already in place: %s\n' "$BUN_LINK"
  fi
fi

# ── Install the Telegram plugin ──────────────────────────────────────────────
#
# Claude Code's plugin install only accepts marketplace identifiers — local
# paths are not supported. Install the official marketplace version to get
# the plugin registered and the server binary in place, then immediately
# patch the skills with the local versions that have per-project state dir
# support (the marketplace version hardcodes the global path).

if command -v claude >/dev/null 2>&1; then
  printf '\nInstalling Telegram plugin...\n'
  if claude plugin install telegram@claude-plugins-official 2>/dev/null; then
    printf 'Plugin installed: telegram@claude-plugins-official\n'
  else
    printf 'Plugin may already be installed.\n'
  fi
else
  printf '\nclaude not found on PATH — skipping plugin install.\n'
  printf 'Run this after logging in:\n'
  printf '  claude plugin install telegram@claude-plugins-official\n'
  printf 'Then re-run install.sh to patch skills and install dependencies.\n'
fi

# ── Patch skills in the installed plugin cache ───────────────────────────────
#
# The marketplace version's skills hardcode ~/.claude/channels/telegram/ and
# don't know about per-project state dirs. Copy the local versions over the
# cached files so /telegram:access and /telegram:configure resolve the right
# path. Safe to re-run — just overwrites files.

TELEGRAM_CACHE=$(ls -d "$HOME/.claude/plugins/cache/claude-plugins-official/telegram/"*/ 2>/dev/null | head -1)
if [[ -n "$TELEGRAM_CACHE" ]] && [[ -d "$TELEGRAM_CACHE/skills" ]]; then
  printf 'Patching skills in %s...\n' "$TELEGRAM_CACHE"
  for skill in access configure; do
    src="$SCRIPT_DIR/skills/$skill/SKILL.md"
    dst="$TELEGRAM_CACHE/skills/$skill/SKILL.md"
    if [[ -f "$src" ]] && [[ -f "$dst" ]]; then
      cp "$src" "$dst"
      printf '  Updated: skills/%s/SKILL.md\n' "$skill"
    fi
  done
elif [[ -z "$TELEGRAM_CACHE" ]]; then
  printf 'Note: plugin cache not found — skills will be patched on next run.\n'
fi

# ── Run bun install for plugin dependencies ──────────────────────────────────
#
# server.ts depends on grammy and @modelcontextprotocol/sdk. Run bun install
# in the repo directory so the server can start. This is safe to re-run.

if [[ -f "$SCRIPT_DIR/package.json" ]]; then
  if [[ -n "$BUN_BIN" ]]; then
    REAL_BUN="$(readlink -f "$BUN_BIN" 2>/dev/null || printf '%s' "$BUN_BIN")"
    printf '\nInstalling plugin dependencies...\n'
    "$REAL_BUN" install --no-summary --cwd "$SCRIPT_DIR" 2>/dev/null && \
      printf 'Dependencies ready.\n' || \
      printf 'Warning: bun install failed — plugin may not start correctly.\n'
  else
    printf '\nWarning: bun not available; skipping dependency install.\n'
    printf 'Run manually:  bun install --cwd %s\n' "$SCRIPT_DIR"
  fi
fi

# ── Check PATH ───────────────────────────────────────────────────────────────

printf '\n'
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  printf 'Note: %s is not on your PATH.\n' "$INSTALL_DIR"
  printf 'Add this to your shell profile (~/.bashrc or ~/.zshrc):\n\n'
  printf '  export PATH="%s:$PATH"\n\n' "$INSTALL_DIR"
  printf 'Then restart your shell or run:  source ~/.bashrc\n\n'
fi

# ── Next steps ───────────────────────────────────────────────────────────────

printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
printf 'Installation complete! Next steps:\n\n'
printf '  1. Run claude-gram from your project directory:\n'
printf '       cd /path/to/your/project\n'
printf '       claude-gram\n\n'
printf '     (First run will prompt for a project ID and bot token.)\n\n'
printf '  2. Watch for this line confirming the bot is live:\n'
printf '       telegram channel: polling as @YourBotName\n\n'
printf '  3. DM your bot on Telegram. It will reply with a code:\n'
printf '       Pairing required — run in Claude Code:\n'
printf '       /telegram:access pair <code>\n\n'
printf '  4. Run that command in the Claude session to approve yourself.\n'
printf '     The bot will confirm: "Paired! Say hi to Claude."\n\n'
printf '  5. Consider locking down access once paired:\n'
printf '       /telegram:access policy allowlist\n'
printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
