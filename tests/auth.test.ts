// tests/auth.test.ts
import { test, expect } from 'bun:test'
import { createHmac } from 'node:crypto'
import { validateInitData } from '../lib/auth.ts'

const TOKEN = '1234:test'
const USER = { id: 42, first_name: 'Jason', username: 'jperr' }

// Mirror of Telegram's signing algorithm, to produce valid fixtures.
function sign(p: URLSearchParams, token: string): string {
  const c = new URLSearchParams(p)
  c.delete('hash')
  // Byte-wise lexicographic sort, matching the spec (not locale-dependent).
  const dcs = [...c.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([k, v]) => `${k}=${v}`).join('\n')
  const secret = createHmac('sha256', 'WebAppData').update(token).digest()
  return createHmac('sha256', secret).update(dcs).digest('hex')
}

test('valid initData returns the user', () => {
  const p = new URLSearchParams({
    query_id: 'q1',
    user: JSON.stringify(USER),
    auth_date: String(Math.floor(Date.now() / 1000)),
  })
  p.set('hash', sign(p, TOKEN))
  expect(validateInitData(p.toString(), TOKEN).id).toBe(42)
})

test('handles URL-encoded values (first_name with space)', () => {
  const p = new URLSearchParams({
    query_id: 'q2',
    user: JSON.stringify({ id: 7, first_name: 'Ann Marie' }),
    auth_date: String(Math.floor(Date.now() / 1000)),
  })
  p.set('hash', sign(p, TOKEN))
  expect(validateInitData(p.toString(), TOKEN).first_name).toBe('Ann Marie')
})

test('tampered hash throws', () => {
  const p = new URLSearchParams({
    user: JSON.stringify(USER),
    auth_date: String(Math.floor(Date.now() / 1000)),
  })
  p.set('hash', '00'.repeat(32))
  expect(() => validateInitData(p.toString(), TOKEN)).toThrow(/hash mismatch/)
})

test('expired initData throws', () => {
  const p = new URLSearchParams({
    user: JSON.stringify(USER),
    auth_date: String(Math.floor(Date.now() / 1000) - 7200),
  })
  p.set('hash', sign(p, TOKEN))
  expect(() => validateInitData(p.toString(), TOKEN)).toThrow(/expired/)
})

test('wrong bot token throws', () => {
  const p = new URLSearchParams({
    user: JSON.stringify(USER),
    auth_date: String(Math.floor(Date.now() / 1000)),
  })
  p.set('hash', sign(p, TOKEN))
  expect(() => validateInitData(p.toString(), '9999:wrong')).toThrow(/hash mismatch/)
})

test('missing user throws', () => {
  const p = new URLSearchParams({ auth_date: String(Math.floor(Date.now() / 1000)) })
  p.set('hash', sign(p, TOKEN))
  expect(() => validateInitData(p.toString(), TOKEN)).toThrow(/missing user/)
})
