import { mount } from '@vue/test-utils'
import { describe, expect, it, vi } from 'vitest'
import { nextTick } from 'vue'
import MinimizedCardView from '../../app/components/app/MinimizedCardView.vue'

vi.stubGlobal('ResizeObserver', class {
  observe() {}
  disconnect() {}
})

async function createCard() {
  const wrapper = mount(MinimizedCardView, { props: { name: '云笔记' } })
  await nextTick()
  await nextTick()
  return wrapper
}

describe('minimized application card', () => {
  it('exposes separate restore and end controls', async () => {
    const wrapper = await createCard()
    await wrapper.get('[aria-label="恢复云笔记"]').trigger('click')
    expect(wrapper.emitted('resume')).toHaveLength(1)
    expect(wrapper.emitted('end')).toBeUndefined()
    await wrapper.get('[aria-label="结束云笔记"]').trigger('click')
    expect(wrapper.emitted('end')).toHaveLength(1)
    wrapper.unmount()
  })

  it('renders the native webpage snapshot and updates it on the next minimize', async () => {
    const wrapper = await createCard()
    expect(wrapper.text()).toContain('暂无法预览')
    await wrapper.setProps({ previewImage: 'data:image/jpeg;base64,first' })
    expect(wrapper.get('.page-preview img').attributes('src')).toBe('data:image/jpeg;base64,first')
    expect(wrapper.get('.page-preview img').attributes('alt')).toBe('云笔记收起时的网页预览')
    expect(wrapper.text()).not.toContain('暂无法预览')
    await wrapper.setProps({ previewImage: 'data:image/jpeg;base64,second' })
    expect(wrapper.get('.page-preview img').attributes('src')).toBe('data:image/jpeg;base64,second')
    wrapper.unmount()
  })

  it('prevents duplicate actions while the native operation is pending', async () => {
    const wrapper = await createCard()
    await wrapper.setProps({ pending: true })
    expect(wrapper.findAll('button').every(button => button.attributes('disabled') !== undefined)).toBe(true)
    expect(wrapper.get('aside').attributes('aria-busy')).toBe('true')
    expect(wrapper.text()).not.toContain('轻点恢复')
    wrapper.unmount()
  })

  it('does not interpret a drag as a restore click', async () => {
    const wrapper = await createCard()
    const card = wrapper.get('aside')
    const element = card.element as HTMLElement
    element.setPointerCapture = vi.fn()
    element.hasPointerCapture = vi.fn(() => false)
    await card.trigger('pointerdown', { pointerId: 1, isPrimary: true, button: 0, clientX: 80, clientY: 100 })
    await card.trigger('pointermove', { pointerId: 1, clientX: 130, clientY: 160 })
    await card.trigger('pointerup', { pointerId: 1, clientX: 130, clientY: 160 })
    await wrapper.get('.restore').trigger('click', { detail: 0 })
    expect(wrapper.emitted('resume')).toBeUndefined()
    // A real keyboard gesture must still work after moving the card.
    await wrapper.get('.restore').trigger('keydown', { key: 'Enter' })
    await wrapper.get('.restore').trigger('click', { detail: 0 })
    expect(wrapper.emitted('resume')).toHaveLength(1)
    wrapper.unmount()
  })
})
