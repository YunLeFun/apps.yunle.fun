import { getRouterParam, setResponseHeader } from 'h3'
import { requireWebBuildMember } from '../../utils/web-build-access'
import { requireWebBuildEditor } from '../../utils/web-build-config'
import { getEditableWebBuild, getOwnedWebBuild } from '../../utils/web-build-storage'

export default defineEventHandler(async (event) => {
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
  requireWebBuildEditor(event)
  const { user, canCollaborate } = await requireWebBuildMember(event)
  const id = getRouterParam(event, 'id') || ''
  return canCollaborate ? getEditableWebBuild(id, user.uid) : getOwnedWebBuild(id, user.uid)
})
