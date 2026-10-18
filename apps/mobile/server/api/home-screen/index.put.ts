import { readBody, setResponseHeader } from 'h3'
import { requireRegisteredCloudbaseUser } from '../../utils/cloudbase-auth'
import { putHomeScreen } from '../../utils/home-screen'

export default defineEventHandler(async (event) => {
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
  const user = await requireRegisteredCloudbaseUser(event)
  return putHomeScreen(user.uid, await readBody<unknown>(event))
})
