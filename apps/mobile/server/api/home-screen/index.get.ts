import { getQuery, setResponseHeader } from 'h3'
import { requestedHomeSchema } from '../../domain/home-screen'
import { requireRegisteredCloudbaseUser } from '../../utils/cloudbase-auth'
import { getHomeScreen } from '../../utils/home-screen'

export default defineEventHandler(async (event) => {
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
  const user = await requireRegisteredCloudbaseUser(event)
  // Clients that understand folders ask for `?schema=2`; older ones keep schema 1.
  return getHomeScreen(user.uid, undefined, requestedHomeSchema(getQuery(event).schema))
})
