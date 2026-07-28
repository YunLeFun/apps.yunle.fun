import { createError, getRouterParam } from 'h3'
import { submitOwnedAppToPublicMarket } from '../../../utils/app-submissions'
import { requireVerifiedCloudbaseUser } from '../../../utils/cloudbase-auth'

export default defineEventHandler(async (event) => {
  const user = await requireVerifiedCloudbaseUser(event)
  const appId = getRouterParam(event, 'id')?.trim()
  if (!appId)
    throw createError({ statusCode: 400, message: '应用 ID 必填' })
  return submitOwnedAppToPublicMarket(user, appId)
})
