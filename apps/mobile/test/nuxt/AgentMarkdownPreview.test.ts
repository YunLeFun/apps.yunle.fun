import { flushPromises, mount } from '@vue/test-utils'
import { describe, expect, it } from 'vitest'

describe('agent markdown preview', () => {
  async function mountPreview(content: string, final = true) {
    const AgentMarkdownPreview = (await import('../../app/components/agent/MarkdownPreview.vue')).default
    const wrapper = mount(AgentMarkdownPreview, {
      props: {
        content,
        final,
      },
    })

    await flushPromises()
    await wrapper.vm.$nextTick()
    return wrapper
  }

  it('renders common markdown while streaming', async () => {
    const wrapper = await mountPreview([
      '## 推荐',
      '',
      '- **CloudBase CLI**',
      '- `pnpm dev`',
      '',
      '```ts',
      'const ok = true',
      '```',
    ].join('\n'), false)

    expect(wrapper.find('strong').text()).toBe('CloudBase CLI')
    expect(wrapper.find('code').text()).toContain('pnpm dev')
    expect(wrapper.find('ul').exists()).toBe(true)
  })

  it('escapes raw html from model output', async () => {
    const wrapper = await mountPreview('<script>alert(1)</script><b>bold</b>')

    expect(wrapper.html()).not.toContain('<script>')
    expect(wrapper.html()).not.toContain('<b>bold</b>')
    expect(wrapper.text()).toContain('<script>alert(1)</script>')
    expect(wrapper.text()).toContain('<b>bold</b>')
  })

  it('keeps safe links and rejects unsafe protocols', async () => {
    const wrapper = await mountPreview('[官网](https://docs.cloudbase.net) [bad](javascript:alert(1))')

    const safeLink = wrapper.find('a[href="https://docs.cloudbase.net"]')
    expect(safeLink.exists()).toBe(true)
    expect(safeLink.attributes('target')).toBe('_blank')
    expect(safeLink.attributes('rel')).toContain('noopener')
    expect(safeLink.attributes('rel')).toContain('noreferrer')
    expect(wrapper.html()).not.toContain('javascript:alert')
    expect(wrapper.text()).toContain('bad')
  })
})
