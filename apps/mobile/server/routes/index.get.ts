import { createError, setResponseHeader } from 'h3'

export default defineEventHandler(async (event) => {
  const html = await useStorage('assets:server').getItem<string>('app-landing.html')
  if (!html)
    throw createError({ statusCode: 503, statusMessage: 'App 下载页暂不可用' })

  setResponseHeader(event, 'Content-Type', 'text/html; charset=utf-8')
  return html
})
