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
    const result = await membership.join(workshopId, {
      uid: user.uid,
      name: user.name || user.handle,
      avatar: user.picture,
    })
    setResponseHeader(event, 'Cache-Control', 'private, no-store')
    return result
  }
  catch (error: unknown) {
    rethrowWorkshopMembershipError(error)
  }
})
