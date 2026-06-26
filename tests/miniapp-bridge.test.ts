// tests/miniapp-bridge.test.ts
import { test, expect } from 'bun:test'
import { MiniAppBridge, miniappKey, type SSEEvent } from '../lib/miniapp-bridge.ts'

test('miniappKey formats correctly', () => {
  expect(miniappKey(42)).toBe('miniapp:42')
  expect(miniappKey('abc')).toBe('miniapp:abc')
})

test('emitText delivers to registered subscriber', () => {
  const bridge = new MiniAppBridge()
  const key = 'miniapp:1'
  const received: SSEEvent[] = []
  const unregister = bridge.register(key, (e) => received.push(e))

  const n = bridge.emitText(key, ['hello', 'world'])
  expect(n).toBe(2)
  expect(received.length).toBe(2)
  expect(received[0]).toMatchObject({ type: 'message', text: 'hello' })
  expect(received[1]).toMatchObject({ type: 'message', text: 'world' })
  unregister()
})

test('emitText to no subscriber returns 0', () => {
  const bridge = new MiniAppBridge()
  const n = bridge.emitText('miniapp:ghost', ['x'])
  expect(n).toBe(0)
})

test('emitEdit replaces by id', () => {
  const bridge = new MiniAppBridge()
  const key = 'miniapp:1'
  const received: SSEEvent[] = []
  bridge.register(key, (e) => received.push(e))

  bridge.emitText(key, ['orig'])
  bridge.emitEdit(key, received[0].id, 'replaced')

  expect(received.length).toBe(2)
  expect(received[1]).toMatchObject({ type: 'edit', id: received[0].id, text: 'replaced' })
})

test('emitDone signals end', () => {
  const bridge = new MiniAppBridge()
  const key = 'miniapp:1'
  const received: SSEEvent[] = []
  bridge.register(key, (e) => received.push(e))

  bridge.emitDone(key)
  expect(received.length).toBe(1)
  expect(received[0]).toMatchObject({ type: 'done' })
  expect(typeof received[0].id).toBe('string')
})

test('emitError delivers', () => {
  const bridge = new MiniAppBridge()
  const key = 'miniapp:1'
  const received: SSEEvent[] = []
  bridge.register(key, (e) => received.push(e))

  bridge.emitError(key, 'boom')
  expect(received.length).toBe(1)
  expect(received[0]).toMatchObject({ type: 'error', text: 'boom' })
})

test('unregister stops delivery', () => {
  const bridge = new MiniAppBridge()
  const key = 'miniapp:1'
  const received: SSEEvent[] = []
  const unregister = bridge.register(key, (e) => received.push(e))

  bridge.emitText(key, ['a'])
  unregister()
  bridge.emitText(key, ['b'])
  expect(received.length).toBe(1)
})

test('broadcast removes a throwing writer', () => {
  const bridge = new MiniAppBridge()
  const key = 'miniapp:1'
  const bad = () => { throw new Error('dead') }
  bridge.register(key, bad)
  expect(bridge.hasSubscriber(key)).toBe(true)

  bridge.emitText(key, ['x'])
  expect(bridge.hasSubscriber(key)).toBe(false)
})

test('lastEventId advances', () => {
  const bridge = new MiniAppBridge()
  const key = 'miniapp:1'
  bridge.register(key, () => {})

  expect(bridge.lastEventId(key)).toBeUndefined()
  bridge.emitText(key, ['a'])
  const id1 = bridge.lastEventId(key)
  expect(typeof id1).toBe('string')
  bridge.emitText(key, ['b'])
  const id2 = bridge.lastEventId(key)
  expect(id2).not.toBe(id1)
})
