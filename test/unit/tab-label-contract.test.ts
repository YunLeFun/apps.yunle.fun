import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const tabsSource = readFileSync(
  new URL('../../app/pages/tabs.vue', import.meta.url),
  'utf8',
)
const tabsArchitecture = readFileSync(
  new URL('../../docs/product/tabs-architecture.md', import.meta.url),
  'utf8',
)

describe('core tab label contract', () => {
  it('keeps the 云 / 乐 / 坊 naming easter egg documented and intact', () => {
    const labels = [...tabsSource.matchAll(/<IonLabel>([^<]+)<\/IonLabel>/g)]
      .map(match => match[1])

    expect(labels.slice(0, 3)).toEqual(['云居', '寻乐', '工坊'])
    expect(tabsArchitecture).toContain('连起来正好是“**云乐坊**”')
    expect(tabsArchitecture).toContain('不要把第三个 Tab 单独重命名为“云乐坊”或“市场”')
  })
})
