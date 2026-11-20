import { getQuery, setResponseHeader } from 'h3'
import { requireWebBuildMember } from '../../utils/web-build-access'
import { getWebBuildTestSession, requireWebBuildEditor } from '../../utils/web-build-config'
import { listWebBuilds } from '../../utils/web-build-storage'

export default defineEventHandler(async (event) => {
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
  requireWebBuildEditor(event)
  const user = await requireWebBuildMember(event)
  return listWebBuilds(user.uid, getQuery(event).includeShared === 'true' && !getWebBuildTestSession(event))
})
