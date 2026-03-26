#!/usr/bin/env bash
set -euo pipefail

# uninstall.sh — Remove claude-gram and the Telegram plugin from this machine.
#
# Usage:
#   ./uninstall.sh                 Remove claude-gram + plugin, keep state dirs
#   ./uninstall.sh --purge         Also delete all Telegram state (tokens, access, inboxes)
#   ./uninstall.sh --project <id>  Also clean TELEGRAM env from that project's settings

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
    # Only remove if it points into ~/.bun (our symlink) or to itself (broken loop)
    if [[ "$target" == "$HOME/.bun"* ]] || [[ "$target" == "$link" ]]; then
      rm -f "$link"
      printf 'Removed bun symlink: %s\n' "$link"
    else
      printf 'Skipped bun symlink (points to %s — not ours)\n' "$target"
    fi
  fi
done

# ── Remove node_modules in this repo ─────────────────────────────────────────

if [[ -d "$SCRIPT_DIR/node_modules" ]]; then
  rm -rf "$SCRIPT_DIR/node_modules"
  printf 'Removed: %s/node_modules\n' "$SCRIPT_DIR"
fi

# ── Uninstall the Claude plugin ───────────────────────────────────────────────

# Find the claude binary — it may not be on $PATH in all shell contexts
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
  printf '\nUninstalling Telegram plugin...\n'
  if "$CLAUDE_BIN" plugin uninstall telegram@claude-plugins-official 2>/dev/null; then
    printf 'Plugin uninstalled.\n'
  else
    printf 'Plugin not installed or already removed.\n'
  fi
else
  printf '\nclaude not found — skipping plugin uninstall.\n'
  printf 'Run manually if needed:  claude plugin uninstall telegram@claude-plugins-official\n'
fi

# Remove plugin cache directory
TELEGRAM_CACHE=$(ls -d "$HOME/.claude/plugins/cache/claude-plugins-official/telegram/"*/ 2>/dev/null | head -1)
if [[ -n "$TELEGRAM_CACHE" ]]; then
  rm -rf "$TELEGRAM_CACHE"
  printf 'Removed plugin cache: %s\n' "$TELEGRAM_CACHE"
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
  else
    printf 'No settings.local.json found at %s\n' "$settings"
  fi
fi

# ── Purge state directories ───────────────────────────────────────────────────

if $PURGE; then
  printf '\n--purge: removing all Telegram state directories...\n'
  STATE_ROOT="$HOME/.claude/channels/telegram"
  if [[ -d "$STATE_ROOT" ]]; then
    rm -rf "$STATE_ROOT"
    printf 'Removed: %s\n' "$STATE_ROOT"
  else
    printf 'State dir not found (already clean): %s\n' "$STATE_ROOT"
  fi
else
  printf '\nState dirs kept (tokens, access lists, inboxes preserved).\n'
  printf 'Use --purge to also delete: ~/.claude/channels/telegram/\n'
fi

printf '\nDone.\n'
