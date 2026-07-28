import { readBody } from 'h3'
import { createAppSubmission } from '../../utils/app-submissions'
import { requireVerifiedCloudbaseUser } from '../../utils/cloudbase-auth'

export default defineEventHandler(async (event) => {
  const user = await requireVerifiedCloudbaseUser(event)
  return createAppSubmission(user, await readBody(event))
})
