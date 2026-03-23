#!/usr/bin/env bash
set -euo pipefail

# install.sh — Install claude-gram and the Telegram plugin for Claude Code.
# Symlinks claude-gram to a directory on PATH and installs the plugin.

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

# ── Install the Telegram plugin ──────────────────────────────────────────────

if command -v claude >/dev/null 2>&1; then
  printf '\nInstalling Telegram plugin for Claude Code...\n'
  claude plugin install telegram@claude-plugins-official 2>/dev/null && \
    printf 'Plugin installed: telegram@claude-plugins-official\n' || \
    printf 'Plugin may already be installed (or claude is not logged in).\n'
else
  printf '\nclaude not found on PATH — skipping plugin install.\n'
  printf 'Run this later:  claude plugin install telegram@claude-plugins-official\n'
fi

# ── Check PATH ───────────────────────────────────────────────────────────────

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  printf '\nNote: %s is not on your PATH.\n' "$INSTALL_DIR"
  printf 'Add this to your shell profile (~/.bashrc or ~/.zshrc):\n\n'
  printf '  export PATH="%s:$PATH"\n\n' "$INSTALL_DIR"
  printf 'Then restart your shell or run:  source ~/.bashrc\n'
else
  printf '\nDone! Run "claude-gram" from any project directory to get started.\n'
fi
