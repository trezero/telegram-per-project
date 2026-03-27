#!/usr/bin/env bash
set -euo pipefail

# install.sh — Install claude-gram and ensure bun is available.
#
# The plugin itself is loaded by Claude Code via --plugin-dir (development)
# or marketplace install. This script only handles:
#   1. Ensuring bun is installed (plugin runtime)
#   2. Copying claude-gram onto PATH

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_BOT="$SCRIPT_DIR/claude-gram"

die() { printf 'install: %s\n' "$1" >&2; exit 1; }

[[ -f "$CLAUDE_BOT" ]] || die "claude-gram not found at $CLAUDE_BOT"

# ── Pick install directory ───────────────────────────────────────────────────

if [[ -d "$HOME/.local/bin" ]]; then
  INSTALL_DIR="$HOME/.local/bin"
elif [[ -d "$HOME/bin" ]]; then
  INSTALL_DIR="$HOME/bin"
else
  INSTALL_DIR="$HOME/.local/bin"
  mkdir -p "$INSTALL_DIR"
fi

if [[ -n "${1:-}" ]]; then
  INSTALL_DIR="$1"
  mkdir -p "$INSTALL_DIR"
fi

TARGET="$INSTALL_DIR/claude-gram"

# ── Install claude-gram ───────────────────────────────────────────────────────

if [[ -e "$TARGET" ]] || [[ -L "$TARGET" ]]; then
  printf 'Updating existing install at %s\n' "$TARGET"
  rm -f "$TARGET"
fi

cp "$CLAUDE_BOT" "$TARGET"
chmod +x "$TARGET"
printf 'Installed: %s\n' "$TARGET"

# ── Ensure bun is installed ──────────────────────────────────────────────────

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

# Symlink bun into INSTALL_DIR so Claude Code can find it when spawning the
# plugin server. Skip if bun is already reachable from INSTALL_DIR.
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

# ── Check PATH ───────────────────────────────────────────────────────────────

printf '\n'
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  printf 'Note: %s is not on your PATH.\n' "$INSTALL_DIR"
  printf 'Add this to your shell profile (~/.bashrc or ~/.zshrc):\n\n'
  printf '  export PATH="%s:$PATH"\n\n' "$INSTALL_DIR"
fi

# ── Next steps ───────────────────────────────────────────────────────────────

printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
printf 'Installation complete! Next steps:\n\n'
printf '  Load the plugin (choose one):\n\n'
printf '    a) For development (this session only):\n'
printf '         claude --plugin-dir %s\n\n' "$SCRIPT_DIR"
printf '    b) Permanent install (when published to a marketplace):\n'
printf '         claude plugin install telegram-per-project@<marketplace>\n\n'
printf '  Then run claude-gram from your project directory:\n'
printf '       cd /path/to/your/project\n'
printf '       claude-gram\n\n'
printf '  First run will prompt for a bot token (via plugin config).\n'
printf '  DM your bot on Telegram to pair, then run:\n'
printf '       /telegram-per-project:access pair <code>\n'
printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
