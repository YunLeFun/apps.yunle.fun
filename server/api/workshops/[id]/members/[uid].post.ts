import { createError, getRouterParam, readBody, setResponseHeader } from 'h3'
import { createCloudbaseWorkshopMembershipModule } from '../../../../domain/workshop-membership/cloudbase'
import { requireVerifiedCloudbaseUser } from '../../../../utils/cloudbase-auth'
import { rethrowWorkshopMembershipError } from '../../../../utils/workshop-errors'

type MembershipDecision = 'approve' | 'reject' | 'remove' | 'block' | 'unblock'

export default defineEventHandler(async (event) => {
  const user = await requireVerifiedCloudbaseUser(event)
  const workshopId = getRouterParam(event, 'id')?.trim().toUpperCase() || ''
  const targetUid = getRouterParam(event, 'uid')?.trim() || ''
  const body = await readBody<unknown>(event)
  const actionValue = isRecord(body) ? body.action : null
  const action = isMembershipDecision(actionValue) ? actionValue : null
  if (!workshopId || !targetUid || !action)
    throw createError({ statusCode: 400, message: '坊客操作参数无效' })

  try {
    const membership = createCloudbaseWorkshopMembershipModule()
    const result = await membership.decide(
      workshopId,
      targetUid,
      action,
      { uid: user.uid },
    )
    setResponseHeader(event, 'Cache-Control', 'private, no-store')
    return { membership: result }
  }
  catch (error: unknown) {
    rethrowWorkshopMembershipError(error)
  }
})

function isMembershipDecision(value: unknown): value is MembershipDecision {
  return value === 'approve'
    || value === 'reject'
    || value === 'remove'
    || value === 'block'
    || value === 'unblock'
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}
