import { readBody } from 'h3'
import { requireVerifiedCloudbaseUser } from '../../utils/cloudbase-auth'
import { createPersonalWorkshop } from '../../utils/personal-workshops'

export default defineEventHandler(async (event) => {
  const user = await requireVerifiedCloudbaseUser(event)
  const workshop = await createPersonalWorkshop(user, await readBody(event))
  return { workshop }
})
