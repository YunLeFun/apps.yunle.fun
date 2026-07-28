import { createError, getRouterParam, readBody, setResponseHeader } from 'h3'
import { requireVerifiedCloudbaseUser } from '../../utils/cloudbase-auth'
import { updatePersonalWorkshop } from '../../utils/personal-workshops'

export default defineEventHandler(async (event) => {
  const user = await requireVerifiedCloudbaseUser(event)
  const workshopId = getRouterParam(event, 'id')?.trim().toUpperCase() || ''
  if (!workshopId)
    throw createError({ statusCode: 400, message: '个人工坊 ID 必填' })
  const workshop = await updatePersonalWorkshop(user, workshopId, await readBody(event))
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
  return { workshop }
})
