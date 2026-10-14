import { mount } from '@vue/test-utils'
import { afterEach, describe, expect, it } from 'vitest'
import { defineComponent, h } from 'vue'
import CatalogBrowser from '../../app/components/workshop/CatalogBrowser.vue'

const iconStub = defineComponent({
  setup() {
    return () => h('span')
  },
})

const categories = [
  { id: 'all', name: '全部', icon: '📱', count: 5 },
  { id: 'design', name: '创意设计', icon: '🎨', count: 2 },
]
const props = {
  categories,
  selected: '全部',
  query: '',
  searchPlaceholder: '搜索应用',
  resultCount: 5,
}

const wrappers: ReturnType<typeof mount>[] = []
const containers: HTMLElement[] = []

afterEach(() => {
  wrappers.splice(0).forEach(wrapper => wrapper.unmount())
  containers.splice(0).forEach(container => container.remove())
})

describe('catalog browser', () => {
  it('offers the same category actions in both navigation modes and keeps slot content while reporting loading and results', async () => {
    const wrapper = mount(CatalogBrowser, {
      props,
      slots: { default: '<p>应用列表内容</p>' },
      global: { stubs: { IonIcon: iconStub } },
    })
    wrappers.push(wrapper)

    const navigations = wrapper.findAll('nav[aria-label="应用分类"]')
    expect(navigations).toHaveLength(2)
    for (const navigation of navigations)
      await navigation.get('button[title="创意设计"]').trigger('click')
    expect(wrapper.emitted('select')).toEqual([['创意设计'], ['创意设计']])

    await wrapper.setProps({ selected: '创意设计', resultCount: 2, loading: true })
    expect(wrapper.get('h1').text()).toBe('创意设计')
    expect(wrapper.get('[role="status"]').text()).toBe('正在加载应用…')
    expect(wrapper.text()).toContain('应用列表内容')
    expect(wrapper.findAll('button[title="创意设计"]').every(button => button.attributes('aria-pressed') === 'true')).toBe(true)

    await wrapper.setProps({ query: '画板', loading: false, resultCount: 1 })
    expect(wrapper.get('h1').text()).toBe('搜索结果')
    expect(wrapper.get('[role="status"]').text()).toBe('1 款应用')
    expect(wrapper.text()).toContain('应用列表内容')
  })

  it('clears a controlled search and returns keyboard focus to the search field without changing category', async () => {
    const container = document.createElement('div')
    document.body.append(container)
    containers.push(container)
    const wrapper = mount(CatalogBrowser, {
      props: {
        ...props,
        selected: '创意设计',
        query: '画板',
        onSearch: (query: string): void => {
          void wrapper.setProps({ query })
        },
      },
      attachTo: container,
      global: { stubs: { IonIcon: iconStub } },
    })
    wrappers.push(wrapper)

    await wrapper.get('button[aria-label="清除搜索"]').trigger('click')

    expect(wrapper.emitted('search')).toEqual([['']])
    expect(wrapper.get<HTMLInputElement>('input[aria-label="搜索应用"]').element.value).toBe('')
    expect(document.activeElement).toBe(wrapper.get('input[aria-label="搜索应用"]').element)
    expect(wrapper.find('button[aria-label="清除搜索"]').exists()).toBe(false)
    expect(wrapper.get('h1').text()).toBe('创意设计')
    expect(wrapper.emitted('select')).toBeUndefined()
  })
})
