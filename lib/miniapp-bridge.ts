// lib/miniapp-bridge.ts
export type SSEEvent =
  | { type: 'message'; id: string; text: string }
  | { type: 'edit'; id: string; text: string }
  | { type: 'done'; id: string }
  | { type: 'error'; id: string; text: string }

export function miniappKey(userId: string | number): string {
  return `miniapp:${userId}`
}

export class MiniAppBridge {
  private subscribers = new Map<string, Set<(event: SSEEvent) => void>>()
  private lastIds = new Map<string, string>()
  private seq = 0

  register(userKey: string, writer: (event: SSEEvent) => void): () => void {
    if (!this.subscribers.has(userKey)) {
      this.subscribers.set(userKey, new Set())
    }
    this.subscribers.get(userKey)!.add(writer)
    return () => {
      const set = this.subscribers.get(userKey)
      if (set) {
        set.delete(writer)
        if (set.size === 0) this.subscribers.delete(userKey)
      }
    }
  }

  hasSubscriber(userKey: string): boolean {
    const set = this.subscribers.get(userKey)
    return !!set && set.size > 0
  }

  lastEventId(userKey: string): string | undefined {
    return this.lastIds.get(userKey)
  }

  emitText(userKey: string, chunks: string[]): number {
    let count = 0
    for (const chunk of chunks) {
      const id = `msg-${++this.seq}`
      count += this.broadcast(userKey, { type: 'message', id, text: chunk })
    }
    return count
  }

  emitEdit(userKey: string, id: string, text: string): number {
    return this.broadcast(userKey, { type: 'edit', id, text })
  }

  emitDone(userKey: string): number {
    const id = `done-${++this.seq}`
    return this.broadcast(userKey, { type: 'done', id })
  }

  emitError(userKey: string, text: string): number {
    const id = `err-${++this.seq}`
    return this.broadcast(userKey, { type: 'error', id, text })
  }

  private broadcast(userKey: string, event: SSEEvent): number {
    const set = this.subscribers.get(userKey)
    if (!set || set.size === 0) return 0
    this.lastIds.set(userKey, event.id ?? this.lastIds.get(userKey) ?? '')
    for (const w of [...set]) {
      try {
        w(event)
      } catch {
        set.delete(w)
        if (set.size === 0) this.subscribers.delete(userKey)
      }
    }
    return 1
  }
}
