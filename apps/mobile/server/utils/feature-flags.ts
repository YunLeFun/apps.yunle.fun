export const ASSISTANT_AUDIENCES = ['off', 'members', 'signedIn', 'everyone'] as const
export type AssistantAudience = typeof ASSISTANT_AUDIENCES[number]

export interface AssistantRollout {
  audience: AssistantAudience
  percent: number
}

export interface PublicFeatures {
  assistant: AssistantRollout
}

/**
 * 公开下发的客户端功能开关。只包含放量策略，不包含账号、名单或密钥；
 * 真正的权限仍由各服务端接口（如 app-discovery 的会员校验）判定。
 */
export function resolvePublicFeatures(config: Record<string, unknown>): PublicFeatures {
  return { assistant: resolveAssistantRollout(config.assistantAudience, config.assistantRolloutPercent) }
}

export function resolveAssistantRollout(audience: unknown, percent: unknown): AssistantRollout {
  const value = typeof audience === 'string' ? audience.trim() : ''
  return {
    audience: (ASSISTANT_AUDIENCES as readonly string[]).includes(value) ? value as AssistantAudience : 'members',
    percent: clampPercent(percent),
  }
}

function clampPercent(value: unknown): number {
  const number = typeof value === 'number' ? value : typeof value === 'string' && value.trim() !== '' ? Number(value) : Number.NaN
  if (!Number.isFinite(number))
    return 100
  return Math.min(100, Math.max(0, Math.floor(number)))
}
