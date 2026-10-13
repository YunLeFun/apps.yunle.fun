import { createError, readBody } from 'h3'
import { APPS_COLLECTION, checkAppNameAvailability } from '../../utils/app-submissions'
import { useCloudbaseAdmin } from '../../utils/cloudbase-admin'
import { requireVerifiedCloudbaseUser } from '../../utils/cloudbase-auth'

export default defineEventHandler(async (event) => {
  const user = await requireVerifiedCloudbaseUser(event)
  const body = await readBody<{ name?: string, excludeAppId?: string }>(event)
  const name = body.name?.trim() || ''
  if (!name)
    return { taken: false, nameKey: '' }
  if (name.length > 50) {
    throw createError({
      statusCode: 400,
      statusMessage: '应用名称不能超过 50 个字符',
    })
  }

  const requestedExcludeAppId = body.excludeAppId?.trim() || ''
  let excludeAppId: string | undefined
  if (requestedExcludeAppId) {
    const { db } = useCloudbaseAdmin()
    const { data } = await db.collection(APPS_COLLECTION).doc(requestedExcludeAppId).get()
    const app = (data || [])[0] as { ownerUid?: string } | undefined
    if (app?.ownerUid === user.uid)
      excludeAppId = requestedExcludeAppId
  }

  const result = await checkAppNameAvailability(name, excludeAppId)
  return { taken: !result.available, nameKey: result.nameKey }
})
