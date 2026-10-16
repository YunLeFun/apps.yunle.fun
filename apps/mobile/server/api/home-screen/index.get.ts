import { setResponseHeader } from 'h3'
import { requireRegisteredCloudbaseUser } from '../../utils/cloudbase-auth'
import { getHomeScreen } from '../../utils/home-screen'

export default defineEventHandler(async (event) => {
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
  const user = await requireRegisteredCloudbaseUser(event)
  return getHomeScreen(user.uid)
})
