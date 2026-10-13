import { flushPromises, mount } from '@vue/test-utils'
import { describe, expect, it } from 'vitest'
import UserAvatar from '../../app/components/user/Avatar.vue'

describe('user avatar', () => {
  it('shows the fallback when a configured avatar fails to load', async () => {
    const wrapper = mount(UserAvatar, {
      props: {
        src: 'https://example.com/missing-avatar.png',
        alt: '测试用户',
      },
      slots: {
        fallback: '<span data-testid="avatar-fallback">测</span>',
      },
    })

    await flushPromises()
    await wrapper.get('img').trigger('error')
    await flushPromises()

    expect(wrapper.find('img').exists()).toBe(false)
    expect(wrapper.get('[data-testid="avatar-fallback"]').text()).toBe('测')
    expect(wrapper.emitted('error')).toHaveLength(1)
  })

  it('renders a stable public CloudBase URL without its old signature', async () => {
    const source = 'https://7975-yunlefun-8g7ybcxc7345c490-1325586649.tcb.qcloud.la/avatars/user.jpg?sign=expired&t=1'

    const wrapper = mount(UserAvatar, {
      props: {
        src: source,
        alt: '测试用户',
      },
      slots: {
        fallback: '<span data-testid="avatar-fallback">测</span>',
      },
    })
    await flushPromises()

    expect(wrapper.get('img').attributes('src')).toBe(
      'https://7975-yunlefun-8g7ybcxc7345c490-1325586649.tcb.qcloud.la/avatars/user.jpg',
    )
  })

  it('renders the CloudBase Auth file ID through the configured public origin', async () => {
    const envId = 'yunlefun-8g7ybcxc7345c490'
    const bucket = `7975-${envId}-1325586649`
    const wrapper = mount(UserAvatar, {
      props: {
        src: `cloud://${envId}.${bucket}/avatars/user.jpg`,
        alt: '测试用户',
      },
      slots: {
        fallback: '<span data-testid="avatar-fallback">测</span>',
      },
    })
    await flushPromises()

    expect(wrapper.get('img').attributes('src')).toBe(
      `https://${bucket}.tcb.qcloud.la/avatars/user.jpg`,
    )
  })

  it('shows the fallback immediately when a public CloudBase avatar fails', async () => {
    const wrapper = mount(UserAvatar, {
      props: {
        src: 'https://7975-yunlefun-8g7ybcxc7345c490-1325586649.tcb.qcloud.la/avatars/missing.jpg',
        alt: '测试用户',
      },
      slots: {
        fallback: '<span data-testid="avatar-fallback">测</span>',
      },
    })
    await flushPromises()

    await wrapper.get('img').trigger('error')
    await flushPromises()

    expect(wrapper.find('img').exists()).toBe(false)
    expect(wrapper.get('[data-testid="avatar-fallback"]').text()).toBe('测')
    expect(wrapper.emitted('error')).toHaveLength(1)
  })
})
