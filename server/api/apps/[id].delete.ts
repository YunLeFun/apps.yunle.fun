import { createError, getRouterParam } from 'h3'
import { delistOwnedApp } from '../../utils/app-submissions'
import { requireVerifiedCloudbaseUser } from '../../utils/cloudbase-auth'

export default defineEventHandler(async (event) => {
  const user = await requireVerifiedCloudbaseUser(event)
  const appId = getRouterParam(event, 'id')?.trim()
  if (!appId)
    throw createError({ statusCode: 400, statusMessage: '应用 ID 必填' })
  await delistOwnedApp(user, appId)
  return { success: true }
})
