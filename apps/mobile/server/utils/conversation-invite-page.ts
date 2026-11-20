import type { H3Event } from 'h3'
import { setResponseHeaders, setResponseStatus } from 'h3'

export function conversationInvitePage(event: H3Event, appUrl: string | null, inviteTitle: string, inviteDescription: string) {
  setResponseHeaders(event, {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'private, no-store',
    'Referrer-Policy': 'no-referrer',
    'X-Robots-Tag': 'noindex, nofollow',
  })
  if (!appUrl)
    setResponseStatus(event, 404)
  const title = appUrl ? inviteTitle : '卡片链接有误'
  const description = appUrl ? inviteDescription : '请向分享者索取完整的卡片链接。'
  // The caller builds this URL from a fixed scheme and validated path segments.
  const action = appUrl ? `<a href="${appUrl}">在云乐坊打开</a>` : '<a href="/">返回云乐坊</a>'
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${title} · 云乐坊</title>
  <style>
    :root { font-family: system-ui, sans-serif; color-scheme: light dark; }
    body { margin: 0; background: Canvas; color: CanvasText; }
    main { max-width: 30rem; margin: auto; padding: clamp(2rem, 10vh, 5rem) 1.5rem; }
    h1 { margin: 0; }
    p { margin: 0.75rem 0 1.5rem; line-height: 1.6; }
    a { display: inline-block; padding: 0.75rem 1.25rem; border-radius: 1.5rem; background: #0960cf; color: white; text-decoration: none; }
  </style>
</head>
<body><main><h1>${title}</h1><p>${description}</p>${action}</main></body>
</html>`
}
