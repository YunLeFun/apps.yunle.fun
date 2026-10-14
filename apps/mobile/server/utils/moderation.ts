import type { tms } from 'tencentcloud-sdk-nodejs-tms'
import { Buffer } from 'node:buffer'
import { tms as tencentTms } from 'tencentcloud-sdk-nodejs-tms'

export type ModerationSuggestion = 'Pass' | 'Review' | 'Block'

export interface ModerationResult {
  suggestion: ModerationSuggestion
  label?: string
  subLabel?: string
  keywords?: string[]
  requestId?: string
  error?: string
}

export interface ModerationTaskLog {
  scene: string
  targetId: string
  uid: string
  contentLength: number
  result: ModerationResult
  durationMs: number
}

type TextModerationResponse = Awaited<ReturnType<InstanceType<typeof tms.v20201229.Client>['TextModeration']>>

let cachedClient: InstanceType<typeof tms.v20201229.Client> | null = null
let cachedClientKey = ''

export function buildModerationContent(parts: Array<string | undefined>): string {
  const content = parts
    .map(part => part?.trim())
    .filter((part): part is string => Boolean(part))
    .join('\n')
  return content.slice(0, 9500)
}

export async function moderateText(opts: {
  content: string
  userId: string
  dataId: string
  scene: string
}): Promise<ModerationResult> {
  if (!opts.content.trim())
    return { suggestion: 'Pass' }

  const startedAt = Date.now()
  try {
    const client = useTmsClient()
    const config = useRuntimeConfig()
    const request = {
      Content: Buffer.from(opts.content, 'utf8').toString('base64'),
      BizType: config.tmsBizType || undefined,
      DataId: sanitizeDataId(opts.dataId),
      User: {
        UserId: opts.userId,
      },
      Type: 'TEXT',
      SourceLanguage: 'zh',
    }
    const response = await client.TextModeration(request)
    return normalizeModerationResponse(response)
  }
  catch (error) {
    return {
      suggestion: 'Review',
      error: getErrorMessage(error),
    }
  }
  finally {
    const durationMs = Date.now() - startedAt
    if (durationMs > 4500) {
      console.warn(`[TMS] ${opts.scene} moderation took ${durationMs}ms`)
    }
  }
}

export async function logModerationTask(
  db: { collection: (name: string) => { add: (data: Record<string, unknown>) => Promise<unknown> } },
  task: ModerationTaskLog,
): Promise<void> {
  try {
    await db.collection('moderation_tasks').add({
      scene: task.scene,
      targetId: task.targetId,
      uid: task.uid,
      contentLength: task.contentLength,
      suggestion: task.result.suggestion,
      label: task.result.label || '',
      subLabel: task.result.subLabel || '',
      keywords: task.result.keywords || [],
      requestId: task.result.requestId || '',
      error: task.result.error || '',
      durationMs: task.durationMs,
      createdAt: Date.now(),
    })
  }
  catch (error) {
    console.warn('[Moderation] failed to log task:', getErrorMessage(error))
  }
}

function useTmsClient(): InstanceType<typeof tms.v20201229.Client> {
  const config = useRuntimeConfig()
  const secretId = config.tencentApiSecretId
  const secretKey = config.tencentApiSecretKey
  if (!secretId || !secretKey) {
    throw new Error('TMS 凭证未配置')
  }

  const region = config.tmsRegion || 'ap-guangzhou'
  const cacheKey = `${secretId}:${region}`
  if (cachedClient && cachedClientKey === cacheKey)
    return cachedClient

  const TmsClient = tencentTms.v20201229.Client
  cachedClient = new TmsClient({
    credential: {
      secretId,
      secretKey,
    },
    region,
    profile: {
      httpProfile: {
        endpoint: 'tms.tencentcloudapi.com',
        reqTimeout: 5,
      },
    },
  })
  cachedClientKey = cacheKey
  return cachedClient
}

function normalizeModerationResponse(response: TextModerationResponse): ModerationResult {
  const detail = response.DetailResults?.[0]
  const rawSuggestion = detail?.Suggestion || response.Suggestion
  return {
    suggestion: normalizeSuggestion(rawSuggestion),
    label: detail?.Label || response.Label,
    subLabel: detail?.SubLabel || response.SubLabel,
    keywords: detail?.Keywords || response.Keywords || [],
    requestId: response.RequestId,
  }
}

function normalizeSuggestion(value?: string): ModerationSuggestion {
  if (value === 'Pass' || value === 'Review' || value === 'Block')
    return value
  return 'Review'
}

function sanitizeDataId(dataId: string): string {
  return dataId.replace(/[^\w@#-]/g, '-').slice(0, 64)
}

function getErrorMessage(error: unknown): string {
  if (error instanceof Error)
    return error.message
  if (typeof error === 'string')
    return error
  return 'TMS 审核失败'
}
