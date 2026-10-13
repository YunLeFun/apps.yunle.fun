import { createError, getRouterParam, setResponseHeader } from 'h3'
import { createCloudbaseWorkshopMembershipModule } from '../../../domain/workshop-membership/cloudbase'
import { requireRegisteredCloudbaseUser } from '../../../utils/cloudbase-auth'
import { rethrowWorkshopMembershipError } from '../../../utils/workshop-errors'

export default defineEventHandler(async (event) => {
  const user = await requireRegisteredCloudbaseUser(event)
  const workshopId = getRouterParam(event, 'id')?.trim().toUpperCase() || ''
  if (!workshopId)
    throw createError({ statusCode: 400, message: '个人工坊 ID 必填' })
  try {
    const membership = createCloudbaseWorkshopMembershipModule()
    const result = await membership.leave(workshopId, { uid: user.uid })
    setResponseHeader(event, 'Cache-Control', 'private, no-store')
    return { membership: result }
  }
  catch (error: unknown) {
    rethrowWorkshopMembershipError(error)
  }
})
