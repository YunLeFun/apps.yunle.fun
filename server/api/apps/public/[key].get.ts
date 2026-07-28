import { createError, getRouterParam, setResponseHeader } from 'h3'
import {
  catalogAppViewToRecord,
  createCloudbaseCatalogResolver,
} from '../../../domain/catalog/cloudbase'

const PUBLIC_APP_KEY_RE = /^[\w.-]{1,128}$/

export default defineEventHandler(async (event) => {
  const key = getRouterParam(event, 'key')?.trim() || ''
  if (!PUBLIC_APP_KEY_RE.test(key)) {
    throw createError({
      statusCode: 400,
      statusMessage: '应用标识无效',
    })
  }

  const resolver = createCloudbaseCatalogResolver()
  const view = await resolver.resolveCatalog({ surface: 'public_market' }, null)
  const found = view.apps.find(app => app._id === key || app.slug === key)
  const app = found ? catalogAppViewToRecord(found) : null
  if (!app) {
    throw createError({
      statusCode: 404,
      statusMessage: '应用不存在',
    })
  }

  setResponseHeader(event, 'Cache-Control', 'public, max-age=60, stale-while-revalidate=300')
  return { app }
})
