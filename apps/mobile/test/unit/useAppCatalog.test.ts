import { beforeEach, describe, expect, it, vi } from 'vitest'
import { reactive, ref } from 'vue'
import { useAppCatalog } from '../../app/composables/useAppCatalog'

const api = vi.fn()
const state = new Map<string, ReturnType<typeof ref>>()
const userStore = reactive({
  userInfo: { id: 'user-1' },
})

function workshopApp() {
  return {
    _id: 'private-app-id',
    ownerLogin: 'owner',
    ownerUid: 'owner-1',
    name: '私人工坊应用',
    slug: 'private-app',
    websiteUrl: 'https://private.example.com/',
    isPublic: false,
    audience: 'workshop',
    accessMode: 'invite_only',
    releaseStage: 'stable',
    status: 'approved',
    publicationStatus: 'published',
    createdAt: 1,
    updatedAt: 1,
  }
}

describe('useAppCatalog accessible workshop projection', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    state.clear()
    userStore.userInfo.id = 'user-1'
    vi.stubGlobal('useNuxtApp', () => ({ $api: api }))
    vi.stubGlobal('useUserStore', () => userStore)
    vi.stubGlobal('useState', (key: string, init: () => unknown) => {
      if (!state.has(key))
        state.set(key, ref(init()))
      return state.get(key)
    })
  })

  it('resolves authorized workshop apps without adding them to the public catalog', async () => {
    api.mockImplementation(async (path: string) => {
      if (path === '/api/workshops/joined') {
        return {
          items: [{
            _id: 'ABC234',
            ownerName: '坊主',
            name: '私人工坊',
            joinPolicy: 'approval',
            status: 'active',
          }],
        }
      }
      if (path === '/api/workshops/mine')
        return { management: null }
      if (path === '/api/workshops/ABC234') {
        return {
          surface: 'workshop',
          access: 'active',
          workshop: {
            _id: 'ABC234',
            ownerName: '坊主',
            name: '私人工坊',
            joinPolicy: 'approval',
            status: 'active',
          },
          apps: [workshopApp()],
        }
      }
      throw new Error(`unexpected API call: ${path}`)
    })

    const appCatalog = useAppCatalog()
    await appCatalog.ensureAccessibleLoaded('user-1')

    expect(appCatalog.getApp('private-app')).toMatchObject({
      id: 'private-app-id',
      name: '私人工坊应用',
    })
    expect(appCatalog.catalog.value).not.toContainEqual(
      expect.objectContaining({ id: 'private-app-id' }),
    )
  })

  it('clears private metadata when the active account is removed', async () => {
    api.mockImplementation(async (path: string) => {
      if (path === '/api/workshops/joined')
        return { items: [] }
      if (path === '/api/workshops/mine')
        return { management: null }
      throw new Error(`unexpected API call: ${path}`)
    })

    const appCatalog = useAppCatalog()
    await appCatalog.ensureAccessibleLoaded('user-1')
    await appCatalog.ensureAccessibleLoaded('')

    expect(appCatalog.accessibleApps.value).toEqual([])
  })

  it('does not expose one account private metadata to another account', async () => {
    api.mockImplementation(async (path: string) => {
      if (path === '/api/workshops/joined') {
        return {
          items: [{
            _id: 'ABC234',
            ownerName: '坊主',
            name: '私人工坊',
            joinPolicy: 'approval',
            status: 'active',
          }],
        }
      }
      if (path === '/api/workshops/mine')
        return { management: null }
      if (path === '/api/workshops/ABC234') {
        return {
          surface: 'workshop',
          access: 'active',
          workshop: {
            _id: 'ABC234',
            ownerName: '坊主',
            name: '私人工坊',
            joinPolicy: 'approval',
            status: 'active',
          },
          apps: [workshopApp()],
        }
      }
      throw new Error(`unexpected API call: ${path}`)
    })

    const appCatalog = useAppCatalog()
    await appCatalog.ensureAccessibleLoaded('user-1')
    userStore.userInfo.id = 'user-2'

    expect(appCatalog.getApp('private-app')).toBeUndefined()
    expect(appCatalog.accessibleApps.value).toEqual([])
  })
})
