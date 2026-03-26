#!/usr/bin/env bash
set -euo pipefail

# uninstall.sh — Remove claude-gram and optionally purge Telegram state.
#
# Usage:
#   ./uninstall.sh                 Remove claude-gram symlink and bun symlink
#   ./uninstall.sh --purge         Also delete all Telegram state (tokens, access, inboxes)
#   ./uninstall.sh --project <dir> Also clean TELEGRAM env from that project's settings

PURGE=false
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge)   PURGE=true; shift ;;
    --project) [[ -n "${2:-}" ]] || { printf 'uninstall: --project requires a path\n' >&2; exit 1; }
               PROJECT_DIR="$2"; shift 2 ;;
    -h|--help) cat <<'EOF'
Usage: ./uninstall.sh [options]

Options:
  --purge              Also delete all Telegram state directories (tokens, access.json, inboxes)
  --project <path>     Path to a project directory — removes TELEGRAM_* from its settings.local.json
  -h, --help           Show this help

Without --purge, state dirs are left intact so you can reinstall and resume without re-pairing.
EOF
               exit 0 ;;
    *) printf 'uninstall: unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done

# ── Remove claude-gram symlink ────────────────────────────────────────────────

for dir in "$HOME/.local/bin" "$HOME/bin"; do
  link="$dir/claude-gram"
  if [[ -L "$link" ]]; then
    target="$(readlink "$link")"
    rm -f "$link"
    printf 'Removed: %s (was -> %s)\n' "$link" "$target"
  fi
done

# ── Remove bun symlink (our symlink only — not bun itself) ────────────────────

for dir in "$HOME/.local/bin" "$HOME/bin"; do
  link="$dir/bun"
  if [[ -L "$link" ]]; then
    target="$(readlink -f "$link" 2>/dev/null || readlink "$link")"
    if [[ "$target" == "$HOME/.bun"* ]] || [[ "$target" == "$link" ]]; then
      rm -f "$link"
      printf 'Removed bun symlink: %s\n' "$link"
    fi
  fi
done

# ── Disable the plugin in Claude Code ─────────────────────────────────────────

CLAUDE_BIN=""
if command -v claude >/dev/null 2>&1; then
  CLAUDE_BIN="$(command -v claude)"
else
  for candidate in "$HOME/.local/bin/claude" "$HOME/bin/claude" "/usr/local/bin/claude"; do
    if [[ -x "$candidate" ]]; then
      CLAUDE_BIN="$candidate"
      break
    fi
  done
fi

if [[ -n "$CLAUDE_BIN" ]]; then
  printf '\nDisabling Telegram plugin...\n'
  "$CLAUDE_BIN" plugin disable telegram-per-project 2>/dev/null && \
    printf 'Plugin disabled.\n' || \
    printf 'Plugin not installed or already disabled.\n'
fi

# ── Clean project settings ────────────────────────────────────────────────────

if [[ -n "$PROJECT_DIR" ]]; then
  settings="$PROJECT_DIR/.claude/settings.local.json"
  if [[ -f "$settings" ]]; then
    printf '\nCleaning Telegram env from %s...\n' "$settings"
    python3 - "$settings" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    d = json.load(f)
env = d.get('env', {})
removed = []
for key in ['TELEGRAM_PROJECT_ID', 'TELEGRAM_STATE_DIR']:
    if key in env:
        del env[key]
        removed.append(key)
if not env:
    d.pop('env', None)
with open(path, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
if removed:
    print(f"  Removed from env: {', '.join(removed)}")
else:
    print("  No Telegram env keys found.")
PYEOF
  fi
fi

# ── Purge state directories ───────────────────────────────────────────────────

if $PURGE; then
  printf '\n--purge: removing all Telegram state directories...\n'
  STATE_ROOT="$HOME/.claude/channels/telegram"
  if [[ -d "$STATE_ROOT" ]]; then
    rm -rf "$STATE_ROOT"
    printf 'Removed: %s\n' "$STATE_ROOT"
  fi
  DATA_DIR="$HOME/.claude/plugins/data/telegram-per-project"
  if [[ -d "$DATA_DIR" ]]; then
    rm -rf "$DATA_DIR"
    printf 'Removed: %s\n' "$DATA_DIR"
  fi
else
  printf '\nState dirs kept. Use --purge to also delete them.\n'
fi

printf '\nDone.\n'
