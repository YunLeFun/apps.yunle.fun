import { createError } from 'h3'

export const WEB_BUILD_HOST = 'build.yunle.app'
export const WEB_BUILD_ORIGIN = `https://${WEB_BUILD_HOST}`
export const webBuildIdPattern = /^[a-f0-9]{32}$/

export function webBuildShareUrl(id: string) {
  return `${WEB_BUILD_ORIGIN}/site/${id}`
}

export function webBuildVersionUrl(id: string, releaseId: string) {
  return `${webBuildShareUrl(id)}/${releaseId}.html`
}

export function getWebBuildWriteToken() {
  const token = useRuntimeConfig().webBuildWriteToken
  return typeof token === 'string' && token.length === 64 && /^[a-f0-9]{64}$/.test(token) ? token : null
}

export function webBuildEditorEnabled() {
  const config = useRuntimeConfig()
  return (config.webBuildEnabled === true || /^[\w.:-]{1,128}$/.test(config.webBuildPilotUid || '')) && !!getWebBuildWriteToken()
}

export function requireWebBuildEditor() {
  if (!webBuildEditorEnabled())
    throw createError({ statusCode: 503, statusMessage: 'AI 网页服务暂未开放' })
}
