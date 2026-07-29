import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const iconBoxUrl = new URL('../../app/components/app/IconBox.vue', import.meta.url)

describe('app icon image fallback contract', () => {
  it('falls back to the configured emoji after a remote image fails', () => {
    const source = readFileSync(iconBoxUrl, 'utf8')

    expect(source).toContain('const imageLoadFailed = ref(false)')
    expect(source).toContain('isImageUrl.value && !imageLoadFailed.value')
    expect(source).toContain('@error="imageLoadFailed = true"')
    expect(source).toContain('isImageUrl.value ? props.emoji : props.icon || props.emoji')
  })

  it('retries image rendering when the icon URL changes', () => {
    const source = readFileSync(iconBoxUrl, 'utf8')

    expect(source).toMatch(/watch\(\(\) => props\.icon,[\s\S]*imageLoadFailed\.value = false/)
  })
})
