#!/usr/bin/env bash
set -euo pipefail

# install.sh — Install claude-gram, ensure bun is available, and install the
# official Telegram channel plugin.
#
# claude-gram launches Claude Code with --channels plugin:telegram@claude-plugins-official,
# so that official channel plugin MUST be installed or the channel won't connect.
# This script does three things:
#   1. Copies claude-gram onto PATH
#   2. Ensures bun is installed (channel server runtime)
#   3. Best-effort installs the official telegram@claude-plugins-official plugin
#
# This repo's per-project skills/hooks are still loaded via --plugin-dir at run time.

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

# ── Install the official channel plugin ──────────────────────────────────────
# claude-gram connects via --channels plugin:telegram@claude-plugins-official,
# so that plugin must be present. Best-effort: non-fatal if claude isn't
# authenticated or the marketplace isn't reachable.

CHANNEL_PLUGIN="telegram@claude-plugins-official"
printf '\n'
if command -v claude >/dev/null 2>&1; then
  printf 'Installing channel plugin %s ...\n' "$CHANNEL_PLUGIN"
  if claude plugin install "$CHANNEL_PLUGIN" >/dev/null 2>&1; then
    printf 'Channel plugin installed: %s\n' "$CHANNEL_PLUGIN"
  else
    # Likely already installed, or install needs an interactive session.
    if claude plugin list 2>/dev/null | grep -q "telegram"; then
      printf 'Channel plugin already installed: %s\n' "$CHANNEL_PLUGIN"
    else
      printf 'Warning: could not install %s automatically.\n' "$CHANNEL_PLUGIN"
      printf '  Run this yourself before launching claude-gram:\n'
      printf '    claude plugin install %s\n' "$CHANNEL_PLUGIN"
    fi
  fi
else
  printf 'Warning: claude not on PATH — skipping channel plugin install.\n'
  printf '  After signing in to Claude Code, run:\n'
  printf '    claude plugin install %s\n' "$CHANNEL_PLUGIN"
  printf '  Without it, claude-gram cannot connect (plugin:telegram:telegram will fail).\n'
fi

# ── Next steps ───────────────────────────────────────────────────────────────

printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
printf 'Installation complete! Next steps:\n\n'
printf '  1. Confirm the channel plugin is installed (required):\n'
printf '       claude plugin list | grep telegram\n\n'
printf '     If missing, run:\n'
printf '       claude plugin install %s\n\n' "$CHANNEL_PLUGIN"
printf '  2. From your project directory, launch with the per-project skills:\n'
printf '       cd /path/to/your/project\n'
printf '       claude-gram --plugin-dir %s\n\n' "$SCRIPT_DIR"
printf '     (Add -dsp to also pass --dangerously-skip-permissions.)\n\n'
printf '  3. claude-gram walks you through setup (project ID + bot token).\n\n'
printf '  4. DM your bot on Telegram to get a pairing code, then in the session:\n'
printf '       /telegram-per-project:access pair <code>\n'
printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
