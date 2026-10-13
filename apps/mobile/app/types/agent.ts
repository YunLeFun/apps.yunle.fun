import type { AppIconAssets } from './app'

export type AgentMessageRole = 'user' | 'assistant' | 'system' | 'tool'

export interface AgentProtocolMessage {
  id: string
  role: AgentMessageRole
  content: string
  name?: string
  toolCallId?: string
  toolCalls?: Array<{
    id: string
    type: 'function'
    function: {
      name: string
      arguments: string
    }
  }>
}

export interface AgentToolDefinition {
  name: string
  description: string
  parameters?: Record<string, unknown>
}

export interface AgentRunInput {
  botId: string
  threadId: string
  runId: string
  messages: AgentProtocolMessage[]
  tools: AgentToolDefinition[]
  context: unknown[]
  state: Record<string, unknown>
  forwardedProps: Record<string, unknown>
}

export interface AgentAppCard {
  id?: string
  slug: string
  name: string
  description?: string
  logo?: string
  iconAssets?: AppIconAssets
  emoji?: string
  themeColor?: string
  category?: string
  rating?: number
  ratingCount?: number
  coinCost?: number
  requiresMembership?: boolean
  reason?: string
  websiteUrl?: string
  trustedHosts?: readonly string[]
}

export interface AgentChatMessage {
  id: string
  role: 'user' | 'assistant'
  content: string
  appCards?: readonly AgentAppCard[]
  toolStatus?: string
  status?: 'streaming' | 'done' | 'error'
}

export interface AgentStreamEvent {
  type?: string
  content?: unknown
  reasoning_content?: unknown
  delta?: unknown
  message?: unknown
  code?: unknown
  toolCallId?: unknown
  toolCallName?: unknown
  [key: string]: unknown
}
