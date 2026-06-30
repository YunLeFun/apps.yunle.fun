import type {
  AgentAppCard,
  AgentChatMessage,
  AgentProtocolMessage,
  AgentRunInput,
  AgentStreamEvent,
} from '~/types/agent'
import { computed, readonly, ref, shallowRef } from 'vue'
import { AGENT_SEARCH_APPS_TOOL_NAME, AGENT_TOOL_DEFINITIONS } from '~/utils/agentTools'

const DEFAULT_AGENT_BOT_ID = 'agent-yunlefun-1g1ef4a470aefe98'

type AgentSendMessage = (
  payload: AgentRunInput,
  options?: { timeout?: number },
) => Promise<{ dataStream: AsyncIterable<AgentStreamEvent> }>

interface AgentBot {
  sendMessage: AgentSendMessage
}

export const AGENT_EXAMPLE_PROMPTS = [
  '找一个适合写代码的开发工具',
  '推荐几个好玩的应用',
  '有没有适合整理灵感的工具',
]

function createAgentId(prefix: string) {
  const cryptoApi = globalThis.crypto
  if (cryptoApi?.randomUUID)
    return `${prefix}_${cryptoApi.randomUUID()}`
  return `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2)}`
}

function stringValue(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined
}

function numberValue(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined
}

function booleanValue(value: unknown): boolean | undefined {
  return typeof value === 'boolean' ? value : undefined
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}

function parseMaybeJson(value: unknown): unknown {
  if (typeof value !== 'string')
    return value
  const trimmed = value.trim()
  if (!trimmed)
    return value
  try {
    return JSON.parse(trimmed)
  }
  catch {
    return value
  }
}

function normalizeAgentAppCard(value: unknown): AgentAppCard | null {
  if (!isRecord(value))
    return null

  const slug = stringValue(value.slug) || stringValue(value.appId) || stringValue(value.id)
  const name = stringValue(value.name) || stringValue(value.title)
  if (!slug || !name)
    return null

  const trustedHosts = Array.isArray(value.trustedHosts)
    ? value.trustedHosts.filter((item): item is string => typeof item === 'string' && item.length > 0)
    : undefined

  return {
    id: stringValue(value.id),
    slug,
    name,
    description: stringValue(value.description),
    logo: stringValue(value.logo),
    emoji: stringValue(value.emoji),
    themeColor: stringValue(value.themeColor),
    category: stringValue(value.category),
    rating: numberValue(value.rating),
    ratingCount: numberValue(value.ratingCount),
    coinCost: numberValue(value.coinCost),
    requiresMembership: booleanValue(value.requiresMembership),
    reason: stringValue(value.reason),
    websiteUrl: stringValue(value.websiteUrl),
    trustedHosts,
  }
}

function findCardCandidates(value: unknown): unknown[] {
  const parsed = parseMaybeJson(value)
  if (Array.isArray(parsed))
    return parsed
  if (!isRecord(parsed))
    return []

  const directKeys = ['apps', 'appCards', 'cards', 'items', 'results']
  for (const key of directKeys) {
    const candidate = parsed[key]
    if (Array.isArray(candidate))
      return candidate
  }

  const nestedKeys = ['data', 'result', 'payload']
  for (const key of nestedKeys) {
    const nested = parsed[key]
    const candidates = findCardCandidates(nested)
    if (candidates.length > 0)
      return candidates
  }

  return []
}

export function extractAgentAppCards(value: unknown): AgentAppCard[] {
  return findCardCandidates(value)
    .map(normalizeAgentAppCard)
    .filter((card): card is AgentAppCard => card !== null)
}

function getStreamContent(event: AgentStreamEvent): string {
  if (event.type === 'TEXT_MESSAGE_CONTENT')
    return stringValue(event.delta) || stringValue(event.content) || ''
  if (!event.type)
    return stringValue(event.content) || ''
  return ''
}

function getRunErrorMessage(event: AgentStreamEvent): string | null {
  if (event.type !== 'RUN_ERROR')
    return null
  return stringValue(event.message) || stringValue(event.content) || 'AI 助手暂时不可用'
}

function isUnauthorizedError(error: unknown) {
  if (!isRecord(error))
    return false
  return error.status === 401 || error.statusCode === 401 || error.code === 401 || error.code === '401'
}

function normalizeErrorMessage(error: unknown) {
  if (error instanceof Error)
    return error.message || 'AI 助手暂时不可用'
  if (isRecord(error))
    return stringValue(error.message) || stringValue(error.msg) || 'AI 助手暂时不可用'
  return 'AI 助手暂时不可用'
}

export function useAgentChat() {
  const router = useRouter()
  const config = useRuntimeConfig()
  const { app } = useCloudbase()
  const userStore = useUserStore()
  const { ensureValidToken } = useCloudbaseAuth()
  const { account, isMember, refresh } = useCoin()
  const { searchApps } = useAgentSearchApps()

  const botId = computed(() => String(config.public.agentBotId || DEFAULT_AGENT_BOT_ID))
  const requestTimeoutMs = computed(() => Number(config.public.agentRequestTimeoutMs || 60000))
  const configurationReady = computed(() => Boolean(
    config.public.tcbEnvId
    && config.public.cloudbaseRegion
    && config.public.cloudbaseAccessKey
    && botId.value,
  ))

  const threadId = useState<string>('agent:thread-id', () => createAgentId('thread'))
  const messages = useState<AgentChatMessage[]>('agent:messages', () => [])
  const input = ref('')
  const running = shallowRef(false)
  const reasoning = shallowRef(false)
  const error = shallowRef<string | null>(null)
  const activeRunId = shallowRef<string | null>(null)

  let runSeq = 0

  const hasMessages = computed(() => messages.value.length > 0)
  const canSend = computed(() => configurationReady.value && input.value.trim().length > 0 && !running.value)

  function reset() {
    stop()
    messages.value = []
    input.value = ''
    error.value = null
    reasoning.value = false
    threadId.value = createAgentId('thread')
  }

  function stop() {
    runSeq += 1
    running.value = false
    reasoning.value = false
    activeRunId.value = null
    messages.value = messages.value.map(message =>
      message.status === 'streaming'
        ? {
            ...message,
            content: message.content || (message.appCards?.length ? '' : '已停止'),
            status: 'done',
            toolStatus: undefined,
          }
        : message,
    )
  }

  async function ensureAccess() {
    if (!userStore.isLoggedIn) {
      router.push('/login')
      return false
    }

    if (!account.value)
      await refresh()

    if (!isMember.value) {
      router.push('/membership')
      return false
    }

    return true
  }

  function toProtocolMessages(): AgentProtocolMessage[] {
    return messages.value
      .filter(message => message.role === 'user' || message.content.trim().length > 0)
      .map(message => ({
        id: message.id,
        role: message.role,
        content: message.content,
      }))
  }

  function updateAssistant(id: string, updater: (message: AgentChatMessage) => AgentChatMessage) {
    messages.value = messages.value.map(message =>
      message.id === id ? updater(message) : message,
    )
  }

  function getAssistant(id: string) {
    return messages.value.find(message => message.id === id)
  }

  function updateAssistantToolStatus(id: string, toolStatus: string | undefined) {
    updateAssistant(id, message => ({ ...message, toolStatus }))
  }

  function appendAssistantContent(id: string, content: string) {
    if (!content)
      return
    updateAssistant(id, message => ({ ...message, content: `${message.content}${content}` }))
  }

  function appendAssistantCards(id: string, cards: AgentAppCard[]) {
    if (cards.length === 0)
      return
    updateAssistant(id, (message) => {
      const existing = message.appCards ?? []
      const seen = new Set(existing.map(card => card.slug))
      const next = [...existing]
      for (const card of cards) {
        if (seen.has(card.slug))
          continue
        seen.add(card.slug)
        next.push(card)
      }
      return { ...message, appCards: next }
    })
  }

  function finishAssistant(id: string) {
    updateAssistant(id, (message) => {
      if (message.status === 'error')
        return { ...message, toolStatus: undefined }

      const hasContent = message.content.trim().length > 0
      const hasCards = (message.appCards?.length ?? 0) > 0
      return {
        ...message,
        content: hasContent || hasCards ? message.content : '暂时没有找到匹配的公开应用，可以换个关键词再试。',
        status: 'done',
        toolStatus: undefined,
      }
    })
  }

  async function appendFallbackAppCards(id: string, query: string, isCurrentRun: () => boolean) {
    if (!isCurrentRun())
      return

    const assistant = getAssistant(id)
    if (!assistant || assistant.status === 'error' || (assistant.appCards?.length ?? 0) > 0)
      return

    updateAssistantToolStatus(id, '正在匹配应用')
    try {
      const cards = await searchApps({ query, limit: 6 })
      if (!isCurrentRun())
        return
      appendAssistantCards(id, cards)
    }
    catch {
      // Agent 文本流已经完成，本地卡片兜底失败不应覆盖主回复。
    }
    finally {
      if (isCurrentRun())
        updateAssistantToolStatus(id, undefined)
    }
  }

  function applyStreamEvent(id: string, raw: AgentStreamEvent) {
    if (stringValue(raw.reasoning_content)) {
      reasoning.value = true
      updateAssistantToolStatus(id, '正在思考')
    }

    const runError = getRunErrorMessage(raw)
    if (runError) {
      error.value = runError
      updateAssistant(id, message => ({ ...message, status: 'error', content: message.content || runError, toolStatus: undefined }))
      return
    }

    if (raw.type === 'RUN_STARTED')
      updateAssistantToolStatus(id, '正在连接')
    if (raw.type === 'TOOL_CALL_START')
      updateAssistantToolStatus(id, stringValue(raw.toolCallName) === AGENT_SEARCH_APPS_TOOL_NAME ? '正在检索应用' : '正在调用工具')
    if (raw.type === 'TOOL_CALL_ARGS')
      updateAssistantToolStatus(id, '正在确认条件')
    if (raw.type === 'TOOL_CALL_END')
      updateAssistantToolStatus(id, '正在整理结果')

    const content = getStreamContent(raw)
    if (content) {
      updateAssistantToolStatus(id, undefined)
      appendAssistantContent(id, content)
    }

    const cards = raw.type === 'TOOL_CALL_RESULT'
      ? extractAgentAppCards(raw.content)
      : extractAgentAppCards(raw)
    appendAssistantCards(id, cards)
    if (raw.type === 'TOOL_CALL_RESULT') {
      updateAssistantToolStatus(id, cards.length > 0 ? `找到 ${cards.length} 个应用` : '工具调用完成')
    }

    if (raw.type === 'RUN_FINISHED') {
      updateAssistant(id, message => ({ ...message, status: 'done', toolStatus: undefined }))
    }
  }

  async function runAgent(content: string, options: {
    appendUser: boolean
    retryingAuth: boolean
  }) {
    const trimmed = content.trim()
    if (!trimmed || running.value)
      return false
    if (!configurationReady.value) {
      error.value = 'AI 助手配置未完成'
      return false
    }
    if (!await ensureAccess())
      return false

    const currentSeq = ++runSeq
    const userId = options.appendUser ? createAgentId('msg') : null
    const assistantId = createAgentId('msg')
    const runId = createAgentId('run')
    activeRunId.value = runId
    running.value = true
    reasoning.value = false
    error.value = null

    const assistantMessage: AgentChatMessage = {
      id: assistantId,
      role: 'assistant',
      content: '',
      appCards: [],
      status: 'streaming',
      toolStatus: '正在连接',
    }

    messages.value = [
      ...messages.value,
      ...(userId
        ? [{ id: userId, role: 'user' as const, content: trimmed, status: 'done' as const }]
        : []),
      assistantMessage,
    ]

    const payload: AgentRunInput = {
      botId: botId.value,
      threadId: threadId.value,
      runId,
      messages: toProtocolMessages(),
      tools: AGENT_TOOL_DEFINITIONS,
      context: [],
      state: {},
      forwardedProps: {
        source: 'apps.yunle.fun',
      },
    }

    try {
      const bot = app.ai().bot as unknown as AgentBot
      const result = await bot.sendMessage(payload, { timeout: requestTimeoutMs.value })
      for await (const event of result.dataStream) {
        if (currentSeq !== runSeq)
          break
        applyStreamEvent(assistantId, event)
      }
      if (currentSeq === runSeq) {
        await appendFallbackAppCards(assistantId, trimmed, () => currentSeq === runSeq)
        finishAssistant(assistantId)
      }
      return true
    }
    catch (err) {
      if (!options.retryingAuth && isUnauthorizedError(err) && await ensureValidToken({ force: true })) {
        messages.value = messages.value.filter(message => message.id !== assistantId)
        return runAgent(trimmed, { appendUser: false, retryingAuth: true })
      }

      const message = normalizeErrorMessage(err)
      error.value = message
      updateAssistant(assistantId, assistant => ({
        ...assistant,
        content: assistant.content || message,
        status: 'error',
        toolStatus: undefined,
      }))
      return false
    }
    finally {
      if (currentSeq === runSeq) {
        running.value = false
        reasoning.value = false
        activeRunId.value = null
      }
    }
  }

  async function sendMessage(prompt?: string) {
    const content = prompt ?? input.value
    const sent = await runAgent(content, { appendUser: true, retryingAuth: false })
    if (sent)
      input.value = ''
    return sent
  }

  async function retryLast() {
    const lastUserIndex = messages.value.findLastIndex(message => message.role === 'user')
    if (lastUserIndex < 0)
      return false
    const lastUser = messages.value[lastUserIndex]
    if (!lastUser)
      return false
    messages.value = messages.value.slice(0, lastUserIndex + 1)
    return runAgent(lastUser.content, { appendUser: false, retryingAuth: false })
  }

  return {
    input,
    messages: readonly(messages),
    hasMessages,
    running: readonly(running),
    reasoning: readonly(reasoning),
    error: readonly(error),
    activeRunId: readonly(activeRunId),
    configurationReady,
    botId,
    canSend,
    sendMessage,
    retryLast,
    stop,
    reset,
  }
}
