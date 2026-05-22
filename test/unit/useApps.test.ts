import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useApps } from '../../app/composables/useApps'

// --- Mock helpers ---

function createMockDb() {
  const mockDoc = {
    get: vi.fn(),
    update: vi.fn(),
    remove: vi.fn(),
  }
  const mockCollection = {
    where: vi.fn().mockReturnThis(),
    orderBy: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
    get: vi.fn(),
    add: vi.fn(),
    doc: vi.fn(() => mockDoc),
  }
  const db = {
    collection: vi.fn(() => mockCollection),
    command: {},
  }
  return { db, mockCollection, mockDoc }
}

function createMockAuth() {
  return {
    getSession: vi.fn(),
    getUser: vi.fn(),
  }
}

function createMockUserStore(overrides: Record<string, any> = {}) {
  return {
    isLoggedIn: false,
    userInfo: { id: '', nickname: '', avatar: '' },
    login: vi.fn(),
    logout: vi.fn(),
    ...overrides,
  }
}

let mockAuth: ReturnType<typeof createMockAuth>
let mockDbSetup: ReturnType<typeof createMockDb>
let mockUserStore: ReturnType<typeof createMockUserStore>

// Mock global composables
vi.stubGlobal('useCloudbase', () => ({
  app: { database: () => mockDbSetup.db },
  auth: mockAuth,
}))

vi.stubGlobal('useUserStore', () => mockUserStore)

vi.stubGlobal('useCloudbaseAuth', () => ({
  user: { value: null },
  checkAuthStatus: vi.fn(),
}))

describe('useApps', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockAuth = createMockAuth()
    mockDbSetup = createMockDb()
    mockUserStore = createMockUserStore()
  })

  describe('ensureAuth', () => {
    it('已登录且 userStore 有 id 时直接返回 id', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123', nickname: 'test' },
      })

      const { getMyApps } = useApps()
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const result = await getMyApps()
      // ensureAuth 应该直接从 userStore 获取 id，不需要调用 auth.getSession
      expect(mockAuth.getSession).not.toHaveBeenCalled()
      expect(result).toEqual([])
    })

    it('userStore 无 id 时通过 CloudBase session 恢复', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: false,
        userInfo: { id: '', nickname: '' },
      })

      mockAuth.getSession.mockResolvedValue({
        data: { session: { access_token: 'token-abc' } },
        error: null,
      })
      mockAuth.getUser.mockResolvedValue({
        data: { user: { uid: 'restored-uid', nickname: 'restored', avatar_url: '' } },
        error: null,
      })

      mockDbSetup.mockCollection.get.mockResolvedValue({
        data: [{ _id: '1', name: 'Test App', _openid: 'restored-uid' }],
      })

      const { getMyApps } = useApps()
      const result = await getMyApps()

      expect(mockAuth.getSession).toHaveBeenCalled()
      expect(mockAuth.getUser).toHaveBeenCalled()
      expect(mockUserStore.login).toHaveBeenCalledWith('token-abc', expect.objectContaining({ id: 'restored-uid' }))
      expect(result).toHaveLength(1)
    })

    it('session 无效时返回空数组（getMyApps）', async () => {
      mockUserStore = createMockUserStore()

      mockAuth.getSession.mockResolvedValue({
        data: null,
        error: { message: 'no session' },
      })

      const { getMyApps } = useApps()
      const result = await getMyApps()

      expect(result).toEqual([])
      expect(mockDbSetup.mockCollection.get).not.toHaveBeenCalled()
    })

    it('session 有效但 getUser 失败时返回 null', async () => {
      mockUserStore = createMockUserStore()

      mockAuth.getSession.mockResolvedValue({
        data: { session: { access_token: 'token-abc' } },
        error: null,
      })
      mockAuth.getUser.mockResolvedValue({
        data: null,
        error: { message: 'user not found' },
      })

      const { getMyAppBySlug } = useApps()
      const result = await getMyAppBySlug('test-slug')

      expect(result).toBeNull()
    })

    it('auth.getSession 异常时优雅处理', async () => {
      mockUserStore = createMockUserStore()
      mockAuth.getSession.mockRejectedValue(new Error('Network error'))

      const { getMyApps } = useApps()
      const result = await getMyApps()

      expect(result).toEqual([])
    })
  })

  describe('getMyApps', () => {
    it('返回用户的所有应用', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123', nickname: 'test' },
      })

      const apps = [
        { _id: '1', name: 'App A', _openid: 'user-123' },
        { _id: '2', name: 'App B', _openid: 'user-123' },
      ]
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: apps })

      const { getMyApps } = useApps()
      const result = await getMyApps()

      expect(result).toEqual(apps)
      expect(mockDbSetup.mockCollection.where).toHaveBeenCalledWith({ _openid: 'user-123' })
      expect(mockDbSetup.mockCollection.orderBy).toHaveBeenCalledWith('updatedAt', 'desc')
      expect(mockDbSetup.mockCollection.limit).toHaveBeenCalledWith(100)
    })
  })

  describe('getMyAppById', () => {
    it('返回匹配的应用', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123', nickname: 'test' },
      })

      const app = { _id: 'doc-1', name: 'My App', _openid: 'user-123' }
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [app] })

      const { getMyAppById } = useApps()
      const result = await getMyAppById('doc-1')

      expect(result).toEqual(app)
      expect(mockDbSetup.mockCollection.where).toHaveBeenCalledWith({ _id: 'doc-1', _openid: 'user-123' })
    })

    it('未找到时返回 null', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123', nickname: 'test' },
      })

      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { getMyAppById } = useApps()
      const result = await getMyAppById('nonexistent')

      expect(result).toBeNull()
    })

    it('数据库异常时返回 null', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123', nickname: 'test' },
      })

      mockDbSetup.mockCollection.get.mockRejectedValue(new Error('DB error'))

      const { getMyAppById } = useApps()
      const result = await getMyAppById('doc-1')

      expect(result).toBeNull()
    })
  })

  describe('getMyAppBySlug', () => {
    it('通过 slug 查找用户自己的应用', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123', nickname: 'test' },
      })

      const app = { _id: 'doc-1', name: 'My App', slug: 'my-app', _openid: 'user-123' }
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [app] })

      const { getMyAppBySlug } = useApps()
      const result = await getMyAppBySlug('my-app')

      expect(result).toEqual(app)
      expect(mockDbSetup.mockCollection.where).toHaveBeenCalledWith({ slug: 'my-app', _openid: 'user-123' })
    })

    it('未认证时返回 null', async () => {
      mockUserStore = createMockUserStore()
      mockAuth.getSession.mockResolvedValue({ data: null, error: { message: 'no session' } })

      const { getMyAppBySlug } = useApps()
      const result = await getMyAppBySlug('my-app')

      expect(result).toBeNull()
    })
  })

  describe('getPublicAppBySlug', () => {
    it('查找公开应用不需要认证', async () => {
      mockUserStore = createMockUserStore()

      const app = { _id: 'doc-1', name: 'Public App', slug: 'public-app', isPublic: true }
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [app] })

      const { getPublicAppBySlug } = useApps()
      const result = await getPublicAppBySlug('public-app')

      expect(result).toEqual(app)
      expect(mockDbSetup.mockCollection.where).toHaveBeenCalledWith({ slug: 'public-app', isPublic: true, status: 'approved' })
      expect(mockAuth.getSession).not.toHaveBeenCalled()
    })
  })

  describe('getAppBySlug', () => {
    it('优先返回自己的应用', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123', nickname: 'test' },
      })

      const myApp = { _id: 'doc-1', name: 'My Version', slug: 'shared-app', _openid: 'user-123' }
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [myApp] })

      const { getAppBySlug } = useApps()
      const result = await getAppBySlug('shared-app')

      expect(result).toEqual(myApp)
    })

    it('自己没有时回退到公开应用', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123', nickname: 'test' },
      })

      const publicApp = { _id: 'doc-2', name: 'Public App', slug: 'other-app', isPublic: true }
      mockDbSetup.mockCollection.get
        .mockResolvedValueOnce({ data: [] }) // getMyAppBySlug 返回空
        .mockResolvedValueOnce({ data: [publicApp] }) // getPublicAppBySlug 返回

      const { getAppBySlug } = useApps()
      const result = await getAppBySlug('other-app')

      expect(result).toEqual(publicApp)
    })
  })

  describe('createApp', () => {
    it('已登录时成功创建应用', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123', nickname: 'test', login: 'testuser' },
      })

      mockDbSetup.mockCollection.add.mockResolvedValue({ id: 'new-doc-id' })

      const { createApp } = useApps()
      const result = await createApp({
        name: 'New App',
        slug: 'new-app',
        isPublic: true,
      })

      expect(result).toBe('new-doc-id')
      expect(mockDbSetup.mockCollection.add).toHaveBeenCalledWith(
        expect.objectContaining({
          name: 'New App',
          slug: 'new-app',
          isPublic: true,
          status: 'pending',
          ownerLogin: 'testuser',
        }),
      )
    })

    it('未登录时抛出错误', async () => {
      mockUserStore = createMockUserStore()
      mockAuth.getSession.mockResolvedValue({ data: null, error: { message: 'no session' } })

      const { createApp } = useApps()
      await expect(createApp({
        name: 'New App',
        slug: 'new-app',
        isPublic: true,
      })).rejects.toThrow('请先登录')
    })

    it('创建时自动设置时间戳', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123', nickname: 'test' },
      })

      mockDbSetup.mockCollection.add.mockResolvedValue({ id: 'new-id' })

      const before = Date.now()
      const { createApp } = useApps()
      await createApp({ name: 'Test', slug: 'test', isPublic: true })
      const after = Date.now()

      const addCall = mockDbSetup.mockCollection.add.mock.calls[0][0]
      expect(addCall.createdAt).toBeGreaterThanOrEqual(before)
      expect(addCall.createdAt).toBeLessThanOrEqual(after)
      expect(addCall.updatedAt).toBe(addCall.createdAt)
    })
  })

  describe('updateApp', () => {
    it('成功更新应用并设置 updatedAt', async () => {
      mockDbSetup.mockDoc.update.mockResolvedValue({})

      const before = Date.now()
      const { updateApp } = useApps()
      await updateApp('doc-1', { name: 'Updated Name' })
      const after = Date.now()

      expect(mockDbSetup.db.collection).toHaveBeenCalledWith('apps')
      expect(mockDbSetup.mockCollection.doc).toHaveBeenCalledWith('doc-1')
      const updateCall = mockDbSetup.mockDoc.update.mock.calls[0][0]
      expect(updateCall.name).toBe('Updated Name')
      expect(updateCall.updatedAt).toBeGreaterThanOrEqual(before)
      expect(updateCall.updatedAt).toBeLessThanOrEqual(after)
    })
  })

  describe('deleteApp', () => {
    it('成功删除应用', async () => {
      mockDbSetup.mockDoc.remove.mockResolvedValue({})

      const { deleteApp } = useApps()
      await deleteApp('doc-1')

      expect(mockDbSetup.mockCollection.doc).toHaveBeenCalledWith('doc-1')
      expect(mockDbSetup.mockDoc.remove).toHaveBeenCalled()
    })
  })

  describe('isSlugTaken', () => {
    it('公开数据中存在则返回 true', async () => {
      mockUserStore = createMockUserStore()
      mockAuth.getSession.mockResolvedValue({ data: null, error: { message: 'no session' } })

      mockDbSetup.mockCollection.get.mockResolvedValue({
        data: [{ slug: 'taken-slug' }],
      })

      const { isSlugTaken } = useApps()
      const result = await isSlugTaken('taken-slug')

      expect(result).toBe(true)
    })

    it('公开数据中不存在但自己的数据中存在则返回 true', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123', nickname: 'test' },
      })

      mockDbSetup.mockCollection.get
        .mockResolvedValueOnce({ data: [] }) // 公开数据中不存在
        .mockResolvedValueOnce({ data: [{ slug: 'my-slug' }] }) // 自己数据中存在

      const { isSlugTaken } = useApps()
      const result = await isSlugTaken('my-slug')

      expect(result).toBe(true)
    })

    it('不存在任何数据中则返回 false', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123', nickname: 'test' },
      })

      mockDbSetup.mockCollection.get
        .mockResolvedValueOnce({ data: [] }) // 公开数据中不存在
        .mockResolvedValueOnce({ data: [] }) // 自己数据中也不存在

      const { isSlugTaken } = useApps()
      const result = await isSlugTaken('new-slug')

      expect(result).toBe(false)
    })
  })
})
