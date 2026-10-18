import { getAppSubmissionAccess } from '../../utils/app-submissions'
import { requireRegisteredCloudbaseUser } from '../../utils/cloudbase-auth'

export default defineEventHandler(async (event) => {
  const user = await requireRegisteredCloudbaseUser(event)
  return getAppSubmissionAccess(user)
})
