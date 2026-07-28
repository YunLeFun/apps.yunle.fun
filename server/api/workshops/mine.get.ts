import { setResponseHeader } from 'h3'
import { requireRegisteredCloudbaseUser } from '../../utils/cloudbase-auth'
import { getOwnedWorkshopManagement } from '../../utils/personal-workshops'

export default defineEventHandler(async (event) => {
  const user = await requireRegisteredCloudbaseUser(event)
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
  return {
    management: await getOwnedWorkshopManagement(user),
  }
})
