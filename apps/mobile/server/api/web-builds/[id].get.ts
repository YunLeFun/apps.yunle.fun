import { getRouterParam, setResponseHeader } from 'h3'
import { requireWebBuildMember } from '../../utils/web-build-access'
import { requireWebBuildEditor } from '../../utils/web-build-config'
import { getOwnedWebBuild } from '../../utils/web-build-storage'

export default defineEventHandler(async (event) => {
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
  requireWebBuildEditor()
  const user = await requireWebBuildMember(event)
  return getOwnedWebBuild(getRouterParam(event, 'id') || '', user.uid)
})
