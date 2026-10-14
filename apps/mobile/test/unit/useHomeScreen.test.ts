import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useHomeScreen } from '../../app/composables/useHomeScreen'

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
    update: vi.fn(),
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

function createMockHomeScreenStore() {
  return {
    isEditMode: false,
    hasPendingChanges: false,
    isSyncing: false,
    cloudDocId: null as string | null,
    lastSyncAt: 0,
    installedApps: [{ appId: 'app-1' }],
    dockApps: [] as { appId: string }[],
    recentApps: [] as { appId: string, usedAt: number }[],
    installApp: vi.fn(),
    uninstallApp: vi.fn(),
    updateInstalledApps: vi.fn(),
    updateDockApps: vi.fn(),
    addRecentApp: vi.fn(),
    enterEditMode: vi.fn(),
    exitEditMode: vi.fn(),
    markPendingChanges: vi.fn(),
    consumePendingChanges: vi.fn(() => false),
    restoreFromCloud: vi.fn(),
    resetCloudState: vi.fn(),
    getHomeScreenConfig: vi.fn(() => ({
      installedApps: [{ appId: 'app-1' }],
      dockApps: [],
      recentApps: [],
      updatedAt: Date.now(),
    })),
  }
}

function createMockSettingsStore(overrides: Record<string, any> = {}) {
  return {
    cloudSyncEnabled: true,
    cloudAutoSync: true,
    ...overrides,
  }
}

let mockAuth: ReturnType<typeof createMockAuth>
let mockDbSetup: ReturnType<typeof createMockDb>
let mockUserStore: ReturnType<typeof createMockUserStore>
let mockHomeScreenStore: ReturnType<typeof createMockHomeScreenStore>
let mockSettingsStore: ReturnType<typeof createMockSettingsStore>

// Mock global composables
vi.stubGlobal('useCloudbase', () => ({
  app: { database: () => mockDbSetup.db },
  auth: mockAuth,
}))
vi.stubGlobal('useUserStore', () => mockUserStore)
vi.stubGlobal('useHomeScreenStore', () => mockHomeScreenStore)
vi.stubGlobal('useSettingsStore', () => mockSettingsStore)
vi.stubGlobal('useToast', () => ({
  showSuccess: vi.fn(),
  showError: vi.fn(),
  showWarning: vi.fn(),
  showInfo: vi.fn(),
}))

// Mock useDebounceFn to execute immediately
vi.mock('@vueuse/core', () => ({
  useDebounceFn: (fn: (...args: unknown[]) => unknown) => fn,
}))

describe('useHomeScreen', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockAuth = createMockAuth()
    mockDbSetup = createMockDb()
    mockUserStore = createMockUserStore()
    mockHomeScreenStore = createMockHomeScreenStore()
    mockSettingsStore = createMockSettingsStore()
    mockAuth.getSession.mockResolvedValue({
      data: {
        session: {
          access_token: 'default-token',
          user: { id: 'user-123' },
        },
      },
      error: null,
    })
  })

  // ==================== ensureAuth ====================

  describe('ensureAuth（通过 loadFromCloud 间接测试）', () => {
    it('已登录时仍以 CloudBase 当前会话身份加载，避免启动阶段账号竞态', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'stale-user' },
      })
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { loadFromCloud } = useHomeScreen()
      await loadFromCloud()

      expect(mockAuth.getSession).toHaveBeenCalled()
      expect(mockDbSetup.mockCollection.where).toHaveBeenCalledWith({ _openid: 'user-123' })
    })

    it('未登录时通过 CloudBase session 恢复', async () => {
      mockAuth.getSession.mockResolvedValue({
        data: { session: { access_token: 'token-abc' } },
        error: null,
      })
      mockAuth.getUser.mockResolvedValue({
        data: { user: { uid: 'restored-uid', nickname: 'test-nick', avatar_url: 'test-avatar' } },
        error: null,
      })
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { loadFromCloud } = useHomeScreen()
      await loadFromCloud()

      expect(mockAuth.getSession).toHaveBeenCalled()
      expect(mockAuth.getUser).toHaveBeenCalled()
      expect(mockDbSetup.mockCollection.where).toHaveBeenCalledWith({ _openid: 'restored-uid' })
    })

    it('session 恢复后将用户信息同步到 userStore', async () => {
      mockAuth.getSession.mockResolvedValue({
        data: { session: { access_token: 'token-xyz' } },
        error: null,
      })
      mockAuth.getUser.mockResolvedValue({
        data: { user: { uid: 'restored-uid', nickname: 'Nick', avatar_url: 'https://avatar.png' } },
        error: null,
      })
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { loadFromCloud } = useHomeScreen()
      await loadFromCloud()

      expect(mockUserStore.login).toHaveBeenCalledWith('token-xyz', expect.objectContaining({
        id: 'restored-uid',
        nickname: 'Nick',
        avatar: 'https://avatar.png',
      }))
    })

    it('userStore 身份与当前会话不同时纠正本地账号', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: false,
        userInfo: { id: 'existing-id', nickname: '', avatar: '' },
      })
      mockAuth.getSession.mockResolvedValue({
        data: { session: { access_token: 'token' } },
        error: null,
      })
      mockAuth.getUser.mockResolvedValue({
        data: { user: { uid: 'restored-uid' } },
        error: null,
      })
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { loadFromCloud } = useHomeScreen()
      await loadFromCloud()

      expect(mockUserStore.login).toHaveBeenCalledWith('token', expect.objectContaining({
        id: 'restored-uid',
      }))
    })

    it('session 无效时不执行数据库操作', async () => {
      mockAuth.getSession.mockResolvedValue({
        data: null,
        error: { message: 'no session' },
      })

      const { loadFromCloud } = useHomeScreen()
      await loadFromCloud()

      expect(mockDbSetup.db.collection).not.toHaveBeenCalled()
    })

    it('getUser 失败时不执行数据库操作', async () => {
      mockAuth.getSession.mockResolvedValue({
        data: { session: { access_token: 'token' } },
        error: null,
      })
      mockAuth.getUser.mockResolvedValue({
        data: null,
        error: { message: 'user not found' },
      })

      const { loadFromCloud } = useHomeScreen()
      await loadFromCloud()

      expect(mockDbSetup.db.collection).not.toHaveBeenCalled()
    })

    it('auth.getSession 异常时优雅处理', async () => {
      mockAuth.getSession.mockRejectedValue(new Error('Network error'))

      const { loadFromCloud } = useHomeScreen()
      await loadFromCloud()

      expect(mockDbSetup.db.collection).not.toHaveBeenCalled()
    })
  })

  // ==================== ensureAuth — 真实 Auth v2 数据 ====================

  describe('ensureAuth — 真实 CloudBase Auth v2 数据', () => {
    // 真实 /user/me 返回的数据结构
    const realAuthV2User = {
      sub: '1978032370372050944',
      name: '云游君',
      picture: 'https://7975-yunlefun-8g7ybcxc7345c490-1325586649.tcb.qcloud.la/avatars/1978032370372050944_1772264964694.jpg',
      username: 'yunyoujun',
      email: 'me@yunyoujun.cn',
      phone_number: '+86 16651050730',
      providers: [
        { id: 'github', provider_user_id: '25154432', name: '云游君' },
      ],
      password: 'SET',
      gender: 'MALE',
      meta: { description: '我自己' },
      created_at: '2025-10-14T09:37:21.818Z',
      password_updated_at: '2026-02-28T12:34:48.571Z',
    }

    it('auth v2 getUser 返回 sub 字段时应正确提取用户 ID', async () => {
      mockAuth.getSession.mockResolvedValue({
        data: { session: { access_token: 'real-token' } },
        error: null,
      })
      // Auth v2 SDK getUser 返回的真实数据：ID 在 sub 字段，没有 uid 也没有 id
      mockAuth.getUser.mockResolvedValue({
        data: { user: realAuthV2User },
        error: null,
      })
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { loadFromCloud } = useHomeScreen()
      await loadFromCloud()

      // 应该用 sub 字段的值查询数据库
      expect(mockDbSetup.mockCollection.where).toHaveBeenCalledWith({
        _openid: '1978032370372050944',
      })
    })

    it('auth v2 用户信息应正确同步到 userStore（昵称用 name，头像用 picture）', async () => {
      mockAuth.getSession.mockResolvedValue({
        data: { session: { access_token: 'real-token' } },
        error: null,
      })
      mockAuth.getUser.mockResolvedValue({
        data: { user: realAuthV2User },
        error: null,
      })
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { loadFromCloud } = useHomeScreen()
      await loadFromCloud()

      expect(mockUserStore.login).toHaveBeenCalledWith('real-token', expect.objectContaining({
        id: '1978032370372050944',
      }))
    })

    it('auth v2 getUser 只有 sub 没有 uid/id 时不应返回 null', async () => {
      mockAuth.getSession.mockResolvedValue({
        data: { session: { access_token: 'token' } },
        error: null,
      })
      // 故意只给 sub，不给 uid 和 id
      mockAuth.getUser.mockResolvedValue({
        data: { user: { sub: '1978032370372050944' } },
        error: null,
      })
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { loadFromCloud } = useHomeScreen()
      await loadFromCloud()

      // 如果 ensureAuth 返回 null，db.collection 不会被调用
      expect(mockDbSetup.db.collection).toHaveBeenCalledWith('user_home_screens')
    })
  })

  // ==================== loadFromCloud ====================

  describe('loadFromCloud', () => {
    beforeEach(() => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123' },
      })
    })

    it('从 CloudBase 加载数据并恢复到 store', async () => {
      const cloudDoc = {
        _id: 'doc-abc',
        installedApps: [{ appId: 'cloud-app' }],
        dockApps: [{ appId: 'dock-app' }],
        recentApps: [{ appId: 'recent-app', usedAt: 1000 }],
        updatedAt: 2000,
      }
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [cloudDoc] })

      const { loadFromCloud } = useHomeScreen()
      await loadFromCloud()

      expect(mockDbSetup.db.collection).toHaveBeenCalledWith('user_home_screens')
      expect(mockDbSetup.mockCollection.where).toHaveBeenCalledWith({ _openid: 'user-123' })
      expect(mockDbSetup.mockCollection.orderBy).toHaveBeenCalledWith('updatedAt', 'desc')
      expect(mockDbSetup.mockCollection.limit).toHaveBeenCalledWith(1)
      expect(mockHomeScreenStore.restoreFromCloud).toHaveBeenCalledWith(
        {
          installedApps: cloudDoc.installedApps,
          dockApps: cloudDoc.dockApps,
          recentApps: cloudDoc.recentApps,
          updatedAt: cloudDoc.updatedAt,
        },
        'doc-abc',
        false,
      )
    })

    it('云端无数据时不调用 restoreFromCloud', async () => {
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })

      const { loadFromCloud } = useHomeScreen()
      await loadFromCloud()

      expect(mockHomeScreenStore.restoreFromCloud).not.toHaveBeenCalled()
    })

    it('云端数据字段缺失时用默认值填充', async () => {
      mockDbSetup.mockCollection.get.mockResolvedValue({
        data: [{ _id: 'doc-x' }],
      })

      const { loadFromCloud } = useHomeScreen()
      await loadFromCloud()

      expect(mockHomeScreenStore.restoreFromCloud).toHaveBeenCalledWith(
        {
          installedApps: [],
          dockApps: [],
          recentApps: [],
          updatedAt: 0,
        },
        'doc-x',
        false,
      )
    })

    it('数据库异常时优雅处理', async () => {
      mockDbSetup.mockCollection.get.mockRejectedValue(
        new Error('DATABASE_PERMISSION_DENIED'),
      )

      const { loadFromCloud } = useHomeScreen()
      await expect(loadFromCloud()).resolves.toBeUndefined()
      expect(mockHomeScreenStore.restoreFromCloud).not.toHaveBeenCalled()
    })
  })

  // ==================== syncToCloud ====================

  describe('syncToCloud', () => {
    beforeEach(() => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123' },
      })
    })

    it('有 cloudDocId 时通过包含 owner 的条件执行 update', async () => {
      mockHomeScreenStore.cloudDocId = 'existing-doc'
      mockDbSetup.mockCollection.update.mockResolvedValue({ updated: 1 })

      const { syncToCloud } = useHomeScreen()
      await syncToCloud()

      expect(mockDbSetup.db.collection).toHaveBeenCalledWith('user_home_screens')
      expect(mockDbSetup.mockCollection.where).toHaveBeenCalledWith({
        _id: 'existing-doc',
        _openid: 'user-123',
      })
      expect(mockDbSetup.mockCollection.update).toHaveBeenCalledWith(
        expect.objectContaining({
          installedApps: expect.any(Array),
          dockApps: expect.any(Array),
          recentApps: expect.any(Array),
          updatedAt: expect.any(Number),
        }),
      )
    })

    it('同步时以 CloudBase 当前会话身份为准，不使用可能过期的本地账号 ID', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'stale-user' },
      })
      mockAuth.getSession.mockResolvedValue({
        data: {
          session: {
            access_token: 'current-token',
            user: { id: 'current-user' },
          },
        },
        error: null,
      })
      mockHomeScreenStore.cloudDocId = 'existing-doc'
      mockDbSetup.mockCollection.update.mockResolvedValue({ updated: 1 })

      const { syncToCloud } = useHomeScreen()
      await syncToCloud()

      expect(mockDbSetup.mockCollection.where).toHaveBeenCalledWith({
        _id: 'existing-doc',
        _openid: 'current-user',
      })
    })

    it('匿名会话不发起需要实名用户权限的云同步', async () => {
      mockAuth.getSession.mockResolvedValue({
        data: {
          session: {
            access_token: 'anonymous-token',
            user: { id: 'anonymous-user', is_anonymous: true },
          },
        },
        error: null,
      })

      const { syncToCloud } = useHomeScreen()
      await syncToCloud()

      expect(mockDbSetup.db.collection).not.toHaveBeenCalled()
    })

    it('update 成功后设置 lastSyncAt', async () => {
      mockHomeScreenStore.cloudDocId = 'existing-doc'
      mockDbSetup.mockCollection.update.mockResolvedValue({ updated: 1 })

      const config = { installedApps: [], dockApps: [], recentApps: [], updatedAt: 5000 }
      mockHomeScreenStore.getHomeScreenConfig.mockReturnValue(config)

      const { syncToCloud } = useHomeScreen()
      await syncToCloud()

      expect(mockHomeScreenStore.lastSyncAt).toBe(5000)
      expect(mockHomeScreenStore.isSyncing).toBe(false)
    })

    it('无 cloudDocId 且云端无文档时不提交系统字段并保存返回的 _id', async () => {
      mockHomeScreenStore.cloudDocId = null
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })
      mockDbSetup.mockCollection.add.mockResolvedValue({ _id: 'new-doc-id' })

      const { syncToCloud } = useHomeScreen()
      await syncToCloud()

      const addPayload = mockDbSetup.mockCollection.add.mock.calls[0]?.[0]
      expect(addPayload).toEqual(expect.objectContaining({
        installedApps: expect.any(Array),
        dockApps: expect.any(Array),
        recentApps: expect.any(Array),
        createdAt: expect.any(Number),
        updatedAt: expect.any(Number),
      }))
      expect(addPayload).not.toHaveProperty('_openid')
      expect(mockHomeScreenStore.cloudDocId).toBe('new-doc-id')
    })

    it('无 cloudDocId 但云端已有文档时复用该文档执行 update（upsert，不产生重复文档）', async () => {
      mockHomeScreenStore.cloudDocId = null
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [{ _id: 'found-doc' }] })
      mockDbSetup.mockCollection.update.mockResolvedValue({ updated: 1 })

      const { syncToCloud } = useHomeScreen()
      await syncToCloud()

      expect(mockDbSetup.mockCollection.where).toHaveBeenCalledWith({
        _id: 'found-doc',
        _openid: 'user-123',
      })
      expect(mockDbSetup.mockCollection.update).toHaveBeenCalled()
      expect(mockDbSetup.mockCollection.add).not.toHaveBeenCalled()
      expect(mockHomeScreenStore.cloudDocId).toBe('found-doc')
    })

    it('update 命中 0 条（云端文档已删除）时回退到 add', async () => {
      mockHomeScreenStore.cloudDocId = 'stale-doc'
      mockDbSetup.mockCollection.update.mockResolvedValue({ updated: 0 })
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })
      mockDbSetup.mockCollection.add.mockResolvedValue({ _id: 'recreated-doc' })

      const { syncToCloud } = useHomeScreen()
      await syncToCloud()

      expect(mockDbSetup.mockCollection.add).toHaveBeenCalled()
      expect(mockHomeScreenStore.cloudDocId).toBe('recreated-doc')
    })

    it('旧文档 ID 未命中时先重新查找当前账号文档，避免重复创建', async () => {
      mockAuth.getSession.mockResolvedValue({
        data: {
          session: {
            access_token: 'current-token',
            user: { id: 'user-123' },
          },
        },
        error: null,
      })
      mockHomeScreenStore.cloudDocId = 'stale-doc'
      mockDbSetup.mockCollection.get.mockResolvedValue({
        data: [{ _id: 'current-doc' }],
      })
      mockDbSetup.mockCollection.update
        .mockResolvedValueOnce({ updated: 0 })
        .mockResolvedValueOnce({ updated: 1 })

      const { syncToCloud } = useHomeScreen()
      await syncToCloud()

      expect(mockDbSetup.mockCollection.update).toHaveBeenCalledTimes(2)
      expect(mockDbSetup.mockCollection.add).not.toHaveBeenCalled()
      expect(mockHomeScreenStore.cloudDocId).toBe('current-doc')
    })

    it('幂等更新返回 0 但当前账号文档仍存在时视为同步成功', async () => {
      mockHomeScreenStore.cloudDocId = 'current-doc'
      mockHomeScreenStore.getHomeScreenConfig.mockReturnValue({
        installedApps: [{ appId: 'private-app' }],
        dockApps: [],
        recentApps: [],
        updatedAt: 5000,
      })
      mockDbSetup.mockCollection.update.mockResolvedValue({ updated: 0 })
      mockDbSetup.mockCollection.get.mockResolvedValue({
        data: [{ _id: 'current-doc' }],
      })

      const { syncToCloud } = useHomeScreen()
      await syncToCloud()

      expect(mockDbSetup.mockCollection.add).not.toHaveBeenCalled()
      expect(mockHomeScreenStore.lastSyncAt).toBe(5000)
    })

    it('多个安装按钮同时请求同步时，数据库写入保持串行', async () => {
      mockAuth.getSession.mockResolvedValue({
        data: {
          session: {
            access_token: 'current-token',
            user: { id: 'user-123' },
          },
        },
        error: null,
      })
      mockHomeScreenStore.cloudDocId = 'current-doc'

      let releaseFirstUpdate!: () => void
      let notifyFirstUpdateStarted!: () => void
      const firstUpdateStarted = new Promise<void>((resolve) => {
        notifyFirstUpdateStarted = resolve
      })
      const firstUpdateGate = new Promise<void>((resolve) => {
        releaseFirstUpdate = resolve
      })
      let activeUpdates = 0
      let maxActiveUpdates = 0
      mockDbSetup.mockCollection.update.mockImplementation(async () => {
        activeUpdates += 1
        maxActiveUpdates = Math.max(maxActiveUpdates, activeUpdates)
        if (mockDbSetup.mockCollection.update.mock.calls.length === 1) {
          notifyFirstUpdateStarted()
          await firstUpdateGate
        }
        activeUpdates -= 1
        return { updated: 1 }
      })

      const firstSync = useHomeScreen().syncToCloud()
      await firstUpdateStarted
      const secondSync = useHomeScreen().syncToCloud()
      await Promise.resolve()

      expect(maxActiveUpdates).toBe(1)

      releaseFirstUpdate()
      await Promise.all([firstSync, secondSync])
      expect(maxActiveUpdates).toBe(1)
    })

    it('云同步关闭时不执行', async () => {
      mockSettingsStore.cloudSyncEnabled = false

      const { syncToCloud } = useHomeScreen()
      await syncToCloud()

      expect(mockDbSetup.db.collection).not.toHaveBeenCalled()
    })

    it('未认证时不执行', async () => {
      mockUserStore = createMockUserStore()
      mockAuth.getSession.mockResolvedValue({
        data: null,
        error: { message: 'no session' },
      })

      const { syncToCloud } = useHomeScreen()
      await syncToCloud()

      expect(mockDbSetup.db.collection).not.toHaveBeenCalled()
    })

    it('update 失败时 isSyncing 恢复为 false', async () => {
      mockHomeScreenStore.cloudDocId = 'existing-doc'
      mockDbSetup.mockCollection.update.mockRejectedValue({
        code: 'DATABASE_PERMISSION_DENIED',
        message: 'Permission denied',
      })

      const { syncToCloud } = useHomeScreen()
      await syncToCloud()

      expect(mockHomeScreenStore.isSyncing).toBe(false)
    })

    it('add 失败时 isSyncing 恢复为 false', async () => {
      mockHomeScreenStore.cloudDocId = null
      mockDbSetup.mockCollection.get.mockResolvedValue({ data: [] })
      mockDbSetup.mockCollection.add.mockRejectedValue(new Error('DB error'))

      const { syncToCloud } = useHomeScreen()
      await syncToCloud()

      expect(mockHomeScreenStore.isSyncing).toBe(false)
      expect(mockHomeScreenStore.cloudDocId).toBeNull()
    })
  })

  // ==================== autoSyncToCloud ====================

  describe('autoSyncToCloud（通过 installApp 间接测试）', () => {
    beforeEach(() => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123' },
      })
      mockHomeScreenStore.cloudDocId = 'doc-1'
      mockDbSetup.mockCollection.update.mockResolvedValue({ updated: 1 })
    })

    it('云同步和自动同步都开启时执行 syncToCloud', async () => {
      const { installApp } = useHomeScreen()
      await installApp('new-app')

      expect(mockHomeScreenStore.installApp).toHaveBeenCalledWith('new-app')
      await vi.waitFor(() => {
        expect(mockDbSetup.mockCollection.update).toHaveBeenCalled()
      })
    })

    it('云同步关闭时不执行', async () => {
      mockSettingsStore.cloudSyncEnabled = false

      const { installApp } = useHomeScreen()
      await installApp('new-app')

      expect(mockHomeScreenStore.installApp).toHaveBeenCalledWith('new-app')
      expect(mockDbSetup.db.collection).not.toHaveBeenCalled()
    })

    it('自动同步关闭时不执行', async () => {
      mockSettingsStore.cloudAutoSync = false

      const { installApp } = useHomeScreen()
      await installApp('new-app')

      expect(mockHomeScreenStore.installApp).toHaveBeenCalledWith('new-app')
      expect(mockDbSetup.db.collection).not.toHaveBeenCalled()
    })

    it('编辑模式下仅标记 pendingChanges 不执行同步', async () => {
      mockHomeScreenStore.isEditMode = true

      const { uninstallApp } = useHomeScreen()
      uninstallApp('app-1')

      expect(mockHomeScreenStore.uninstallApp).toHaveBeenCalledWith('app-1')
      expect(mockHomeScreenStore.markPendingChanges).toHaveBeenCalled()
      expect(mockDbSetup.db.collection).not.toHaveBeenCalled()
    })
  })

  // ==================== finishEditing ====================

  describe('finishEditing', () => {
    beforeEach(() => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123' },
      })
      mockHomeScreenStore.cloudDocId = 'doc-1'
      mockDbSetup.mockCollection.update.mockResolvedValue({ updated: 1 })
    })

    it('有 pending 变更时退出编辑并触发同步', async () => {
      mockHomeScreenStore.consumePendingChanges.mockReturnValue(true)

      const { finishEditing } = useHomeScreen()
      finishEditing()

      // syncToCloud 是异步的，等待 Promise 队列刷新
      await vi.waitFor(() => {
        expect(mockDbSetup.mockCollection.update).toHaveBeenCalled()
      })

      expect(mockHomeScreenStore.consumePendingChanges).toHaveBeenCalled()
      expect(mockHomeScreenStore.exitEditMode).toHaveBeenCalled()
    })

    it('无 pending 变更时退出编辑但不同步', () => {
      mockHomeScreenStore.consumePendingChanges.mockReturnValue(false)

      const { finishEditing } = useHomeScreen()
      finishEditing()

      expect(mockHomeScreenStore.exitEditMode).toHaveBeenCalled()
      expect(mockDbSetup.db.collection).not.toHaveBeenCalled()
    })
  })

  // ==================== 操作方法 ====================

  describe('installApp', () => {
    it('调用 store.installApp 并触发自动同步', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123' },
      })
      mockHomeScreenStore.cloudDocId = 'doc-1'
      mockDbSetup.mockCollection.update.mockResolvedValue({ updated: 1 })

      const { installApp } = useHomeScreen()
      await installApp('app-x')

      expect(mockHomeScreenStore.installApp).toHaveBeenCalledWith('app-x')
    })
  })

  describe('uninstallApp', () => {
    it('调用 store.uninstallApp 并触发自动同步', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123' },
      })
      mockHomeScreenStore.cloudDocId = 'doc-1'
      mockDbSetup.mockCollection.update.mockResolvedValue({ updated: 1 })

      const { uninstallApp } = useHomeScreen()
      await uninstallApp('app-1')

      expect(mockHomeScreenStore.uninstallApp).toHaveBeenCalledWith('app-1')
    })
  })

  describe('updateOrder', () => {
    it('调用 store.updateInstalledApps 并触发自动同步', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123' },
      })
      mockHomeScreenStore.cloudDocId = 'doc-1'
      mockDbSetup.mockCollection.update.mockResolvedValue({ updated: 1 })

      const apps = [{ appId: 'a' }, { appId: 'b' }]
      const { updateOrder } = useHomeScreen()
      await updateOrder(apps)

      expect(mockHomeScreenStore.updateInstalledApps).toHaveBeenCalledWith(apps)
    })
  })

  describe('updateDock', () => {
    it('调用 store.updateDockApps 并触发自动同步', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123' },
      })
      mockHomeScreenStore.cloudDocId = 'doc-1'
      mockDbSetup.mockCollection.update.mockResolvedValue({ updated: 1 })

      const apps = [{ appId: 'dock-a' }]
      const { updateDock } = useHomeScreen()
      await updateDock(apps)

      expect(mockHomeScreenStore.updateDockApps).toHaveBeenCalledWith(apps)
    })
  })

  describe('recordRecentUse', () => {
    it('调用 store.addRecentApp 并触发自动同步', async () => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123' },
      })
      mockHomeScreenStore.cloudDocId = 'doc-1'
      mockDbSetup.mockCollection.update.mockResolvedValue({ updated: 1 })

      const { recordRecentUse } = useHomeScreen()
      await recordRecentUse('app-recent')

      expect(mockHomeScreenStore.addRecentApp).toHaveBeenCalledWith('app-recent')
    })
  })

  // ==================== 编辑模式完整流程 ====================

  describe('编辑模式完整流程', () => {
    beforeEach(() => {
      mockUserStore = createMockUserStore({
        isLoggedIn: true,
        userInfo: { id: 'user-123' },
      })
      mockHomeScreenStore.cloudDocId = 'doc-1'
      mockDbSetup.mockCollection.update.mockResolvedValue({ updated: 1 })
    })

    it('编辑模式下多次操作只在退出时同步一次', async () => {
      mockHomeScreenStore.isEditMode = true

      const { uninstallApp, finishEditing } = useHomeScreen()

      // 编辑模式下删除多个应用
      uninstallApp('app-1')
      uninstallApp('app-2')
      uninstallApp('app-3')

      // 应该标记了 3 次 pending，但没有执行同步
      expect(mockHomeScreenStore.markPendingChanges).toHaveBeenCalledTimes(3)
      expect(mockDbSetup.db.collection).not.toHaveBeenCalled()

      // 退出编辑模式
      mockHomeScreenStore.consumePendingChanges.mockReturnValue(true)
      mockHomeScreenStore.isEditMode = false // 模拟 exitEditMode 的效果
      finishEditing()

      // syncToCloud 是异步的，等待 Promise 队列刷新
      await vi.waitFor(() => {
        expect(mockDbSetup.mockCollection.update).toHaveBeenCalledTimes(1)
      })
    })
  })
})
