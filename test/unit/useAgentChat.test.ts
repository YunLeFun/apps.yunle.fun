import type { AgentStreamEvent } from '../../app/types/agent'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ref } from 'vue'
import { extractAgentAppCards, useAgentChat } from '../../app/composables/useAgentChat'

const mockPush = vi.fn()
const mockSendMessage = vi.fn()
const mockSearchApps = vi.fn()
const mockEnsureValidToken = vi.fn()
const mockRefresh = vi.fn()
const stateMap = new Map<string, ReturnType<typeof ref>>()

let mockUserStore: { isLoggedIn: boolean }
let mockCoin: {
  account: { value: unknown }
  isMember: { value: boolean }
  refresh: typeof mockRefresh
}
let mockBot: {
  contextMarker: 'bot'
  sendMessage: typeof mockSendMessage
}
let mockRuntimePublic: Record<string, unknown>
let streamItems: AgentStreamEvent[] = []

async function* makeStream(items: AgentStreamEvent[]) {
  for (const item of items)
    yield item
}

vi.stubGlobal('useRouter', () => ({ push: mockPush }))
vi.stubGlobal('useRuntimeConfig', () => ({
  public: mockRuntimePublic,
}))
vi.stubGlobal('useCloudbase', () => ({
  app: {
    ai: () => ({
      bot: mockBot,
    }),
  },
}))
vi.stubGlobal('useUserStore', () => mockUserStore)
vi.stubGlobal('useCloudbaseAuth', () => ({ ensureValidToken: mockEnsureValidToken }))
vi.stubGlobal('useCoin', () => mockCoin)
vi.stubGlobal('useAgentSearchApps', () => ({ searchApps: mockSearchApps }))
vi.stubGlobal('useState', (key: string, init: () => unknown) => {
  if (!stateMap.has(key))
    stateMap.set(key, ref(init()))
  return stateMap.get(key)
})

describe('agent stream helpers', () => {
  it('extractAgentAppCards parses tool result payloads', () => {
    const cards = extractAgentAppCards(JSON.stringify({
      apps: [
        {
          slug: 'dev-tool',
          name: 'Dev Tool',
          description: 'A developer app',
          themeColor: '#007AFF',
          rating: 4.8,
          reason: '适合开发场景',
        },
        { slug: '', name: 'Invalid' },
      ],
    }))

    expect(cards).toEqual([
      expect.objectContaining({
        slug: 'dev-tool',
        name: 'Dev Tool',
        reason: '适合开发场景',
        rating: 4.8,
      }),
    ])
  })
})

describe('useAgentChat', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    stateMap.clear()
    streamItems = []
    mockUserStore = { isLoggedIn: true }
    mockRuntimePublic = {
      tcbEnvId: 'env-test',
      cloudbaseRegion: 'ap-shanghai',
      cloudbaseAccessKey: 'access-key-test',
      agentBotId: 'agent-test',
      agentRequestTimeoutMs: 1234,
    }
    mockCoin = {
      account: { value: { coin: 100, membership: { isActive: true, level: 'basic', expireAt: Date.now() + 1000 } } },
      isMember: { value: true },
      refresh: mockRefresh,
    }
    mockEnsureValidToken.mockResolvedValue(true)
    mockSearchApps.mockResolvedValue([])
    mockBot = {
      contextMarker: 'bot',
      sendMessage: mockSendMessage,
    }
    mockSendMessage.mockImplementation(async function (this: { contextMarker?: string }) {
      if (this.contextMarker !== 'bot')
        throw new Error('lost bot context')
      return { dataStream: makeStream(streamItems) }
    })
  })

  it('merges content chunks, AG-UI text events, and tool result cards', async () => {
    streamItems = [
      { content: '我找到了' },
      { type: 'TEXT_MESSAGE_CONTENT', delta: '这些应用' },
      {
        type: 'TOOL_CALL_RESULT',
        content: JSON.stringify({
          apps: [
            { slug: 'code-helper', name: 'Code Helper', reason: '适合写代码' },
          ],
        }),
      },
      { type: 'RUN_FINISHED' },
    ]

    const chat = useAgentChat()
    await chat.sendMessage('找一个开发工具')

    expect(mockSendMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        botId: 'agent-test',
        messages: [expect.objectContaining({ role: 'user', content: '找一个开发工具' })],
        tools: [expect.objectContaining({ name: 'search_apps' })],
        context: [],
        state: {},
      }),
      { timeout: 1234 },
    )

    expect(chat.messages.value).toHaveLength(2)
    expect(chat.messages.value[1]).toEqual(expect.objectContaining({
      role: 'assistant',
      content: '我找到了这些应用',
      status: 'done',
      appCards: [
        expect.objectContaining({ slug: 'code-helper', name: 'Code Helper' }),
      ],
    }))
  })

  it('uses local app search as a card fallback when the agent returns text only', async () => {
    streamItems = [
      { content: '可以试试这些开发工具。' },
      { type: 'RUN_FINISHED' },
    ]
    mockSearchApps.mockResolvedValue([
      { slug: 'code-helper', name: 'Code Helper', reason: '本地检索匹配' },
    ])

    const chat = useAgentChat()
    await chat.sendMessage('找一个开发工具')

    expect(mockSearchApps).toHaveBeenCalledWith({ query: '找一个开发工具', limit: 6 })
    expect(chat.messages.value[1]).toEqual(expect.objectContaining({
      content: '可以试试这些开发工具。',
      appCards: [
        expect.objectContaining({ slug: 'code-helper', name: 'Code Helper' }),
      ],
    }))
  })

  it('keeps the agent response when local card fallback fails', async () => {
    streamItems = [
      { content: '先给你几个方向。' },
      { type: 'RUN_FINISHED' },
    ]
    mockSearchApps.mockRejectedValue(new Error('search failed'))

    const chat = useAgentChat()
    await chat.sendMessage('找工具')

    expect(chat.error.value).toBe(null)
    expect(chat.messages.value[1]).toEqual(expect.objectContaining({
      content: '先给你几个方向。',
      status: 'done',
    }))
  })

  it('ignores local card fallback results after stopping the active run', async () => {
    let resolveSearch!: (cards: Array<{ slug: string, name: string }>) => void
    streamItems = [
      { content: '正在整理推荐。' },
      { type: 'RUN_FINISHED' },
    ]
    mockSearchApps.mockReturnValue(new Promise((resolve) => {
      resolveSearch = resolve
    }))

    const chat = useAgentChat()
    const sent = chat.sendMessage('找一个开发工具')
    await vi.waitFor(() => expect(mockSearchApps).toHaveBeenCalled())

    chat.stop()
    resolveSearch([{ slug: 'code-helper', name: 'Code Helper' }])
    await sent

    expect(chat.messages.value[1]?.appCards).toEqual([])
    expect(chat.messages.value[1]?.status).toBe('done')
  })

  it('routes non-members to membership without calling agent', async () => {
    mockCoin.isMember.value = false

    const chat = useAgentChat()
    const sent = await chat.sendMessage('找应用')

    expect(sent).toBe(false)
    expect(mockPush).toHaveBeenCalledWith('/membership')
    expect(mockSendMessage).not.toHaveBeenCalled()
  })

  it('refreshes account snapshot before membership check when missing', async () => {
    mockCoin.account.value = null
    mockCoin.isMember.value = true
    streamItems = [{ content: 'ok' }]

    const chat = useAgentChat()
    await chat.sendMessage('找应用')

    expect(mockRefresh).toHaveBeenCalled()
    expect(mockSendMessage).toHaveBeenCalled()
  })

  it('captures run errors in assistant message', async () => {
    streamItems = [
      { type: 'RUN_ERROR', message: '超出每日限额' },
    ]

    const chat = useAgentChat()
    await chat.sendMessage('找应用')

    expect(chat.error.value).toBe('超出每日限额')
    expect(chat.messages.value[1]).toEqual(expect.objectContaining({
      status: 'error',
      content: '超出每日限额',
    }))
  })

  it('does not call agent when runtime config is incomplete', async () => {
    mockRuntimePublic.cloudbaseAccessKey = ''

    const chat = useAgentChat()
    const sent = await chat.sendMessage('找应用')

    expect(sent).toBe(false)
    expect(chat.error.value).toBe('AI 助手配置未完成')
    expect(mockSendMessage).not.toHaveBeenCalled()
  })
})
