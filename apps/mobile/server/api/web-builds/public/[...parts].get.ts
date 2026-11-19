import { setResponseHeader } from 'h3'
import { webBuildIdPattern } from '../../../utils/web-build-config'
import { getPublicWebBuild, missingWebBuild } from '../../../utils/web-build-storage'

export default defineEventHandler((event) => {
  setResponseHeader(event, 'Cache-Control', 'no-store')
  const parts = event.path.split('?')[0]?.split('/').slice(4) ?? []
  const [id, release] = parts
  if (!id || ![1, 2].includes(parts.length)
    || !parts.every(part => part.length === 32 && webBuildIdPattern.test(part))) {
    missingWebBuild()
  }

  return getPublicWebBuild(id, release)
})
