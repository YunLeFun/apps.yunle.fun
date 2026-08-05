import { beforeAll, describe, expect, it } from 'vitest'

describe('weekly chart navigation', () => {
  beforeAll(async () => {
    await useRouter().isReady()
  })

  it('resolves the public weekly chart route instead of the catch-all 404 page', () => {
    const resolved = useRouter().resolve('/charts/weekly')

    expect(resolved.matched.some(record => record.name === 'charts-weekly')).toBe(true)
  })
})
