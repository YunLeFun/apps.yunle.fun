import { describe, expect, it, vi } from 'vitest'
import { ensureWorkshopForAudience } from '../../app/utils/workshopAudience'

describe('workshop audience provisioning', () => {
  it('opens a default workshop for the first workshop-only app', async () => {
    const workshopModule = {
      getManagement: vi.fn().mockResolvedValue(null),
      create: vi.fn().mockResolvedValue({ _id: '6MU9AG' }),
    }

    await expect(ensureWorkshopForAudience('workshop', workshopModule)).resolves.toBe(true)
    expect(workshopModule.getManagement).toHaveBeenCalledOnce()
    expect(workshopModule.create).toHaveBeenCalledWith({})
  })

  it('does not create another workshop when one already exists', async () => {
    const workshopModule = {
      getManagement: vi.fn().mockResolvedValue({ workshop: { _id: '6MU9AG' } }),
      create: vi.fn(),
    }

    await expect(ensureWorkshopForAudience('workshop', workshopModule)).resolves.toBe(false)
    expect(workshopModule.create).not.toHaveBeenCalled()
  })

  it('does not query workshop state for other audiences', async () => {
    const workshopModule = {
      getManagement: vi.fn(),
      create: vi.fn(),
    }

    await expect(ensureWorkshopForAudience('public', workshopModule)).resolves.toBe(false)
    expect(workshopModule.getManagement).not.toHaveBeenCalled()
    expect(workshopModule.create).not.toHaveBeenCalled()
  })
})
