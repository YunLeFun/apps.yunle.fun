import { getAppSubmissionAccess } from '../../utils/app-submissions'
import { requireCloudbaseUser } from '../../utils/cloudbase-auth'

export default defineEventHandler(async (event) => {
  const user = await requireCloudbaseUser(event)
  return getAppSubmissionAccess(user)
})
