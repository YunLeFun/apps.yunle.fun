import type { H3Event } from 'h3'
import { describe, expect, it } from 'vitest'
import {
  isWorkshopApiPath,
  setWorkshopNoStore,
} from '../../server/utils/workshop-cache'

describe('workshop API cache policy', () => {
  it('sets the private no-store response header', () => {
    const headers = new Map<string, string | number | readonly string[]>()
    const event = {
      node: {
        res: {
          setHeader(name: string, value: string | number | readonly string[]) {
            headers.set(name.toLowerCase(), value)
          },
        },
      },
    } as H3Event

    setWorkshopNoStore(event)

    expect(headers.get('cache-control')).toBe('private, no-store')
  })

  it('matches only the workshop API namespace', () => {
    expect(isWorkshopApiPath('/api/workshops')).toBe(true)
    expect(isWorkshopApiPath('/api/workshops/mine')).toBe(true)
    expect(isWorkshopApiPath('/api/workshop')).toBe(false)
    expect(isWorkshopApiPath('/api/apps/public')).toBe(false)
  })
})
