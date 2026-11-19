import type { H3Event } from 'h3'
import { createError } from 'h3'
import { invokeAccountApi } from './account-api'
import { requireVerifiedCloudbaseUser } from './cloudbase-auth'

const unavailableMessage = '暂时无法核对会员状态，请稍后重试'

export async function requireWebBuildMember(event: H3Event) {
  const user = await requireVerifiedCloudbaseUser(event)
  const config = useRuntimeConfig(event)
  if (config.webBuildEnabled !== true && config.webBuildPilotUid !== user.uid)
    throw createError({ statusCode: 503, message: 'AI 网页服务暂未开放' })
  const snapshot = await invokeAccountApi(event, { action: 'getAccount' }, unavailableMessage) as {
    membership?: { isActive?: unknown, expireAt?: unknown } | null
  } | null
  const membership = snapshot?.membership
  if (typeof membership?.isActive !== 'boolean'
    || (membership.isActive && !Number.isFinite(membership.expireAt))) {
    throw createError({ statusCode: 503, message: unavailableMessage })
  }
  if (!membership.isActive || Number(membership.expireAt) <= Date.now()) {
    throw createError({
      statusCode: 403,
      message: 'AI 制作网页需要有效的云乐坊会员',
      data: { code: 'MEMBERSHIP_REQUIRED' },
    })
  }
  return user
}
