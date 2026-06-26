// lib/auth.ts
import { createHmac, timingSafeEqual } from 'node:crypto'

export type TgUser = {
  id: number
  first_name?: string
  last_name?: string
  username?: string
}

// Validates Telegram Mini App initData per
// https://core.telegram.org/bots/webapps#validating-data-received-via-the-mini-app
// Returns the parsed user on success; throws on any failure.
// NOTE: replay prevention (query_id single-use) is enforced at the HTTP layer,
// not here — this function is pure validation + freshness.
export function validateInitData(
  initData: string,
  botToken: string,
  maxAgeS = 300,
): TgUser {
  const params = new URLSearchParams(initData)
  const hash = params.get('hash')
  const authDate = Number(params.get('auth_date'))
  if (!hash || !authDate) throw new Error('initData missing hash/auth_date')

  const ageS = Date.now() / 1000 - authDate
  if (ageS > maxAgeS) throw new Error(`initData expired (${Math.round(ageS)}s old)`)

  // data-check-string: every key except hash, sorted byte-wise, decoded, newline-joined.
  // URLSearchParams already yields decoded values.
  params.delete('hash')
  const dataCheckString = [...params.entries()]
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([k, v]) => `${k}=${v}`)
    .join('\n')

  const secret = createHmac('sha256', 'WebAppData').update(botToken).digest()
  const calculated = createHmac('sha256', secret).update(dataCheckString).digest('hex')

  const a = Buffer.from(calculated, 'hex')
  const b = Buffer.from(hash, 'hex')
  if (a.length !== b.length || !timingSafeEqual(a, b)) {
    throw new Error('initData hash mismatch')
  }

  const userRaw = params.get('user')
  if (!userRaw) throw new Error('initData missing user')
  return JSON.parse(userRaw) as TgUser
}
