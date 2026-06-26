// lib/session.ts
import { createHmac, timingSafeEqual } from 'node:crypto'

// Long-lived session cookie layer for the Mini App.
//
// The Telegram `initData` flow only validates freshness for ~5 minutes after
// issuance; the HTTP server (task 1.4) mints one of these cookies on a
// successful initData check and then calls `verifySessionCookie` on every
// subsequent request. This keeps auth cheap, side-effect-free, and stateless
// across multi-day sessions (plan review H3).
//
// Cookie format: base64url(JSON{userId, exp}) + "." + base64url(HMAC-SHA256(payload, secret)).

const SECONDS_PER_DAY = 86400

export type SessionCookie = { token: string; expiresAt: number }
export type SessionPayload = { userId: number }

// Mints a signed session cookie for the given Telegram user id.
// `ttlS` is the cookie lifetime in seconds (default: 30 days).
export function mintSessionCookie(
  userId: number,
  secret: string,
  ttlS = 30 * SECONDS_PER_DAY,
): SessionCookie {
  const iat = Math.floor(Date.now() / 1000)
  const exp = iat + ttlS
  const payload = Buffer.from(JSON.stringify({ userId, exp })).toString('base64url')
  const sig = createHmac('sha256', secret).update(payload).digest('base64url')
  return { token: `${payload}.${sig}`, expiresAt: exp }
}

// Verifies a session cookie's signature and expiry.
// Returns `{ userId }` on success, or `null` for any malformed, tampered,
// expired, or wrong-secret token. Never throws — safe to call on raw input.
export function verifySessionCookie(token: string, secret: string): SessionPayload | null {
  if (typeof token !== 'string') return null

  const dot = token.lastIndexOf('.')
  if (dot <= 0 || dot === token.length - 1) return null

  const payloadB64 = token.slice(0, dot)
  const sigB64 = token.slice(dot + 1)

  // Recompute the MAC over the exact payload bytes received, then compare in
  // constant time. If the payload was tampered with, the signatures won't
  // match and we reject without reading untrusted JSON.
  const expectedSig = createHmac('sha256', secret).update(payloadB64).digest('base64url')
  const a = Buffer.from(sigB64)
  const b = Buffer.from(expectedSig)
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null

  // Signature is valid → safe to trust the payload.
  let parsed: { userId?: unknown; exp?: unknown }
  try {
    parsed = JSON.parse(Buffer.from(payloadB64, 'base64url').toString('utf8'))
  } catch {
    return null
  }
  if (parsed === null || typeof parsed !== 'object') return null
  if (typeof parsed.userId !== 'number' || !Number.isFinite(parsed.userId)) return null
  if (typeof parsed.exp !== 'number' || !Number.isFinite(parsed.exp)) return null

  const nowS = Math.floor(Date.now() / 1000)
  if (nowS >= parsed.exp) return null

  return { userId: parsed.userId }
}
