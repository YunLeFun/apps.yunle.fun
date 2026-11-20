import type { H3Event } from 'h3'
import { setTimeout as delay } from 'node:timers/promises'
import { sendStream, setResponseHeaders } from 'h3'

export async function streamConversationSnapshots<T extends { revision: number }>(
  event: H3Event,
  refresh: () => Promise<T>,
  isFinished: (snapshot: T) => boolean,
  interval: (snapshot: T) => number,
  errorCode = 'CARD_UNAVAILABLE',
) {
  let snapshot = await refresh()
  let sentRevision = 0
  let heartbeat = Date.now()
  const deadline = heartbeat + 20_000
  const encoder = new TextEncoder()
  const abort = new AbortController()
  setResponseHeaders(event, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'X-Accel-Buffering': 'no',
  })
  event.node.res.once('close', () => abort.abort())
  return sendStream(event, new ReadableStream<Uint8Array>({
    async pull(controller) {
      try {
        while (!abort.signal.aborted && Date.now() < deadline) {
          if (snapshot.revision > sentRevision) {
            controller.enqueue(encoder.encode(`data: ${JSON.stringify(snapshot)}\n\n`))
            sentRevision = snapshot.revision
            if (isFinished(snapshot))
              controller.close()
            return
          }
          if (Date.now() - heartbeat >= 8_000) {
            controller.enqueue(encoder.encode(': keep-alive\n\n'))
            heartbeat = Date.now()
            return
          }
          // The document is authoritative across function instances.
          await delay(interval(snapshot), undefined, { signal: abort.signal })
          if (!abort.signal.aborted)
            snapshot = await refresh()
        }
      }
      catch {
        if (!abort.signal.aborted)
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({ error: errorCode })}\n\n`))
      }
      controller.close()
    },
    cancel() { abort.abort() },
  }))
}
