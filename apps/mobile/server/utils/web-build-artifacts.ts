import type { WebBuildPage } from './web-build-page'
import { createHash } from 'node:crypto'
import { createError } from 'h3'
import { getWebBuildWriteToken, WEB_BUILD_ORIGIN, webBuildShareUrl } from './web-build-config'
import { renderWebBuildPage } from './web-build-html'

export async function storeWebBuildArtifact(id: string, revision: number, page: WebBuildPage) {
  const token = getWebBuildWriteToken()
  if (!token)
    throw createError({ statusCode: 503, statusMessage: '网页托管暂未配置' })

  const report = `mailto:kf@yunle.fun?subject=${encodeURIComponent('举报云乐坊网页')}&body=${encodeURIComponent(`网页：${webBuildShareUrl(id)}\n版本：${revision}\n原因：`)}`
  const html = renderWebBuildPage(page, report)
  const sha256 = createHash('sha256').update(html).digest('hex')
  const releaseId = createHash('sha256').update(JSON.stringify([id, revision, sha256])).digest('hex').slice(0, 32)
  try {
    const response = await fetch(`${WEB_BUILD_ORIGIN}/_publish/${id}/${releaseId}.html`, {
      method: 'PUT',
      redirect: 'error',
      signal: AbortSignal.timeout(8000),
      headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'text/html; charset=utf-8' },
      body: html,
    })
    if (response.status === 201 || response.status === 204)
      return { releaseId, sha256 }
  }
  catch {
    // Treat a timed out upload as retryable. It uses the same immutable object key.
  }
  throw createError({ statusCode: 503, statusMessage: '网页文件暂时无法保存，请重试' })
}
