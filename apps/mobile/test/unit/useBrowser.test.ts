import { describe, expect, it, vi } from 'vitest'
import { openCatalogAppInBrowser, openInAppBrowser } from '../../app/composables/useBrowser'

const open = vi.fn()
vi.stubGlobal('window', { open })

describe('browser app launch', () => {
  it('opens a catalog application in an isolated browser tab', async () => {
    await openCatalogAppInBrowser({ id: 'cook', websiteUrl: 'https://cook.yunle.fun/home' })
    expect(open).toHaveBeenCalledWith('https://cook.yunle.fun/home', '_blank', 'noopener,noreferrer')
  })

  it('rejects executable URLs and URLs with credentials', async () => {
    await expect(openInAppBrowser('javascript:alert(1)')).rejects.toThrow('Unsupported application URL')
    await expect(openInAppBrowser('https://name:secret@example.com')).rejects.toThrow('Unsupported application URL')
    expect(open).not.toHaveBeenCalled()
  })
})
