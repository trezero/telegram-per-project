// tests/session.test.ts
import { test, expect } from 'bun:test'
import { createHmac } from 'node:crypto'
import { mintSessionCookie, verifySessionCookie } from '../lib/session.ts'

const SECRET = 'super-secret-bot-token'

test('a minted cookie verifies and returns the right userId', () => {
  const { token, expiresAt } = mintSessionCookie(42, SECRET)
  expect(typeof token).toBe('string')
  expect(expiresAt).toBeGreaterThan(Math.floor(Date.now() / 1000))
  expect(verifySessionCookie(token, SECRET)).toEqual({ userId: 42 })
})

test('a tampered cookie returns null', () => {
  const { token } = mintSessionCookie(42, SECRET)
  const [payload, sig] = token.split('.')
  expect(payload).toBeDefined()
  expect(sig).toBeDefined()
  // Flip the userId bytes inside the payload, keep the old signature.
  const tamperedPayload = Buffer.from(payload, 'base64url')
  const json = JSON.parse(tamperedPayload.toString('utf8'))
  json.userId = 99
  const tamperedPayloadB64 = Buffer.from(JSON.stringify(json)).toString('base64url')
  const tampered = `${tamperedPayloadB64}.${sig}`
  expect(verifySessionCookie(tampered, SECRET)).toBeNull()
})

test('an expired cookie returns null', () => {
  // ttl of 0 means exp == now; allow a tiny skew by using a negative ttl.
  const { token } = mintSessionCookie(42, SECRET, -1)
  expect(verifySessionCookie(token, SECRET)).toBeNull()
})

test('a cookie signed with a different secret returns null', () => {
  const { token } = mintSessionCookie(42, SECRET)
  expect(verifySessionCookie(token, 'a-completely-different-secret')).toBeNull()
})

test('a malformed cookie structure returns null (does not throw)', () => {
  expect(verifySessionCookie('not-a-valid-cookie', SECRET)).toBeNull()
  expect(verifySessionCookie('', SECRET)).toBeNull()
  expect(verifySessionCookie('a.b.c', SECRET)).toBeNull()
  // Not valid base64url payload.
  expect(verifySessionCookie('@@@.bbbb', SECRET)).toBeNull()
})

test('a cookie whose payload is JSON null returns null (does not throw)', () => {
  // HMAC is valid, but the payload decodes to JSON `null` — a non-object.
  // Without the object guard, `parsed.userId` would throw a TypeError.
  const payload = Buffer.from('null').toString('base64url')
  const secret = 'test-secret'
  const sig = createHmac('sha256', secret).update(payload).digest('base64url')
  const token = `${payload}.${sig}`
  expect(verifySessionCookie(token, secret)).toBeNull()
})
