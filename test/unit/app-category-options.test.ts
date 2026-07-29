import { describe, expect, it } from 'vitest'
import { getAvailableAppCategories } from '~/utils/appCategories'

describe('getAvailableAppCategories', () => {
  it('始终保留全部并隐藏没有应用的固定分类', () => {
    const categories = getAvailableAppCategories([
      { category: '工具' },
      { category: '工具' },
      { category: '设计' },
    ])

    expect(categories.map(category => category.name)).toEqual([
      '全部',
      '工具',
      '设计',
    ])
  })

  it('支持应用实际使用的非固定分类并忽略空分类', () => {
    const categories = getAvailableAppCategories([
      { category: '音乐' },
      { category: ' 影像 ' },
      { category: '' },
      {},
    ])

    expect(categories.map(category => category.name)).toEqual([
      '全部',
      '音乐',
      '影像',
    ])
  })

  it('空工坊只显示全部', () => {
    expect(getAvailableAppCategories([]).map(category => category.name))
      .toEqual(['全部'])
  })
})
