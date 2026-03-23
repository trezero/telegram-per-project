# Privacy Policy — telegram-per-project

**Last updated:** 2026-03-23

## Overview

This plugin connects a Telegram bot to your local Claude Code session. It does not collect, store, or transmit any data to third-party services beyond what is described below.

## Data flow

1. **Telegram → Your machine:** Inbound messages are received from Telegram's Bot API via long-polling and delivered to your local Claude Code session. Photos are downloaded to your local filesystem (`~/.claude/channels/telegram/inbox/`).

2. **Your machine → Telegram:** Outbound replies, reactions, and edits are sent to Telegram's Bot API using your bot token.

3. **No other destinations.** The plugin does not phone home, send analytics, or communicate with any server other than `api.telegram.org`.

## Data stored locally

All state is stored on your local filesystem under `~/.claude/channels/telegram/`:

| File | Contents |
|---|---|
| `.env` | Your Telegram bot token |
| `access.json` | Access control policy (allowlist, pending pairings, delivery settings) |
| `inbox/` | Downloaded photos from inbound messages |
| `approved/` | Temporary pairing approval signals |

Per-project state follows the same structure under `projects/<id>/`.

## Credentials

- **Bot tokens** are stored in `.env` files with `0600` permissions (owner-read/write only)
- **Access config** is stored in `access.json` with `0600` permissions
- No credentials are transmitted anywhere other than `api.telegram.org`

## Third-party services

The only external service this plugin communicates with is the [Telegram Bot API](https://core.telegram.org/bots/api). Your use of Telegram is subject to [Telegram's Privacy Policy](https://telegram.org/privacy).

## Contact

For questions about this privacy policy, open an issue at https://github.com/trezero/telegram-per-project/issues.
