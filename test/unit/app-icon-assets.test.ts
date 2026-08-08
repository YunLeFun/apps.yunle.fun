import { describe, expect, it } from 'vitest'
import {
  compactAppIconAssets,
  createAppIconAssetsDraft,
  resolveAppIconPresentation,
} from '../../app/utils/appIconAssets'

const assets = {
  appIcon: {
    src: 'https://cdn.example.com/app.png',
    darkSrc: 'https://cdn.example.com/app-dark.png',
  },
  mark: {
    src: 'https://cdn.example.com/mark.png',
    darkSrc: 'https://cdn.example.com/mark-dark.png',
  },
}

describe('app icon assets', () => {
  it('prefers a complete icon for original style and selects its dark variant', () => {
    expect(resolveAppIconPresentation({ assets, preferOriginal: true, dark: true })).toEqual({
      role: 'app-icon',
      source: 'https://cdn.example.com/app-dark.png',
    })
  })

  it('prefers the subject mark for generated styles', () => {
    expect(resolveAppIconPresentation({ assets, preferOriginal: false })).toEqual({
      role: 'mark',
      source: 'https://cdn.example.com/mark.png',
    })
  })

  it('falls back from dark to default, then to a legacy logo and emoji', () => {
    expect(resolveAppIconPresentation({
      assets: { appIcon: { src: '/app.png' } },
      preferOriginal: true,
      dark: true,
    })).toEqual({ role: 'app-icon', source: '/app.png' })
    expect(resolveAppIconPresentation({ legacyIcon: '/legacy.png' })).toEqual({
      role: 'legacy',
      source: '/legacy.png',
    })
    expect(resolveAppIconPresentation({})).toEqual({ role: 'emoji', source: '' })
  })

  it('round-trips form drafts without emitting empty variants', () => {
    const draft = createAppIconAssetsDraft({ mark: { src: '/mark.png' } })
    draft.appIcon.src = '  '
    expect(compactAppIconAssets(draft)).toEqual({
      appIcon: undefined,
      mark: { src: '/mark.png' },
    })
  })
})
