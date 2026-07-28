import type { H3Event } from 'h3'
import { setResponseHeader } from 'h3'

export function isWorkshopApiPath(path: string): boolean {
  return path === '/api/workshops' || path.startsWith('/api/workshops/')
}

export function setWorkshopNoStore(event: H3Event): void {
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
}
