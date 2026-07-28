import { mockNuxtImport } from '@nuxt/test-utils/runtime'
import { flushPromises, mount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import UserAvatar from '../../app/components/user/Avatar.vue'

const mockCreateSignedUrl = vi.fn()

mockNuxtImport('useCloudbase', () => () => ({
  app: {
    storage: {
      from: () => ({
        createSignedUrl: mockCreateSignedUrl,
      }),
    },
  },
}))

describe('user avatar', () => {
  beforeEach(() => {
    mockCreateSignedUrl.mockReset()
  })

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

    expect(wrapper.find('img').exists()).toBe(false)
    expect(wrapper.get('[data-testid="avatar-fallback"]').text()).toBe('测')
    expect(wrapper.emitted('error')).toHaveLength(1)
  })

  it('signs a private CloudBase avatar before rendering it', async () => {
    const source = 'https://7975-yunlefun-8g7ybcxc7345c490-1325586649.tcb.qcloud.la/avatars/user.jpg'
    const signed = `${source}?sign=fresh&t=999`
    mockCreateSignedUrl.mockResolvedValue({
      data: { signedUrl: signed },
      error: null,
    })

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

    expect(mockCreateSignedUrl).toHaveBeenCalledWith('avatars/user.jpg', 3600)
    expect(wrapper.get('img').attributes('src')).toBe(signed)
  })
})
