import { createError, getRouterParam, setResponseHeader } from 'h3'
import { getPublicAppByKey } from '../../../utils/public-apps'

const PUBLIC_APP_KEY_RE = /^[\w.-]{1,128}$/

export default defineEventHandler(async (event) => {
  const key = getRouterParam(event, 'key')?.trim() || ''
  if (!PUBLIC_APP_KEY_RE.test(key)) {
    throw createError({
      statusCode: 400,
      statusMessage: '应用标识无效',
    })
  }

  const app = await getPublicAppByKey(key)
  if (!app) {
    throw createError({
      statusCode: 404,
      statusMessage: '应用不存在',
    })
  }

  setResponseHeader(event, 'Cache-Control', 'public, max-age=60, stale-while-revalidate=300')
  return { app }
})
