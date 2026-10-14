import { getQuery } from 'h3'
import { isAppSlugTaken } from '../../utils/app-submissions'
import { requireVerifiedCloudbaseUser } from '../../utils/cloudbase-auth'

export default defineEventHandler(async (event) => {
  const user = await requireVerifiedCloudbaseUser(event)
  const slug = String(getQuery(event).slug || '').trim().toLowerCase()
  return { taken: await isAppSlugTaken(slug, user.uid) }
})
