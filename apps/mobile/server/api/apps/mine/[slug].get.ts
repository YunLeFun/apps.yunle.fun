import { createError, getRouterParam } from 'h3'
import { getOwnedAppBySlug } from '../../../utils/app-submissions'
import { requireRegisteredCloudbaseUser } from '../../../utils/cloudbase-auth'

export default defineEventHandler(async (event) => {
  const user = await requireRegisteredCloudbaseUser(event)
  const slug = getRouterParam(event, 'slug')?.trim()
  if (!slug)
    throw createError({ statusCode: 400, statusMessage: 'slug 必填' })
  const app = await getOwnedAppBySlug(user, slug)
  if (!app)
    throw createError({ statusCode: 404, statusMessage: '应用不存在或无权访问' })
  return { app }
})
