import { setResponseHeader } from 'h3'
import { requireWebBuildMember } from '../../utils/web-build-access'
import { webBuildEditorEnabled } from '../../utils/web-build-config'
import { getWebBuildRuntimeConfig } from '../../utils/web-build-model'

export default defineEventHandler(async (event) => {
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
  if (!webBuildEditorEnabled() || !getWebBuildRuntimeConfig())
    return { enabled: false }

  await requireWebBuildMember(event)
  return { enabled: true }
})
