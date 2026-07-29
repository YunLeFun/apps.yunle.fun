import { describe, expect, it } from 'vitest'
import { APP_CATEGORIES as MARKET_CATEGORIES } from '~/constants/apps'
import { APP_CATEGORIES as FORM_CATEGORIES } from '~/types/app'

describe('app categories', () => {
  it('exposes games in both the marketplace filter and submission form', () => {
    expect(MARKET_CATEGORIES).toContainEqual({
      id: 'games',
      name: '游戏',
      icon: '🎮',
    })
    expect(FORM_CATEGORIES).toContainEqual({
      label: '游戏',
      icon: '🕹️',
    })
  })
})
