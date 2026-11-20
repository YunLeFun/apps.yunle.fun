import { getRouterParam, setResponseHeader } from 'h3'
import { requireWebBuildMember } from '../../utils/web-build-access'
import { getWebBuildTestSession, requireWebBuildEditor } from '../../utils/web-build-config'
import { getEditableWebBuild, getOwnedWebBuild } from '../../utils/web-build-storage'

export default defineEventHandler(async (event) => {
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
  requireWebBuildEditor(event)
  const user = await requireWebBuildMember(event)
  const id = getRouterParam(event, 'id') || ''
  return getWebBuildTestSession(event) ? getOwnedWebBuild(id, user.uid) : getEditableWebBuild(id, user.uid)
})
