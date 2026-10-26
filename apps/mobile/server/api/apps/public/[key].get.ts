import { createError, getRouterParam, setResponseHeader } from 'h3'
import {
  catalogAppViewToRecord,
  createCloudbaseCatalogResolver,
} from '../../../domain/catalog/cloudbase'
import { publicAppUnavailableReason } from '../../../utils/public-app-availability'

const PUBLIC_APP_KEY_RE = /^[\w.-]{1,128}$/

export default defineEventHandler(async (event) => {
  const key = getRouterParam(event, 'key')?.trim() || ''
  if (!PUBLIC_APP_KEY_RE.test(key)) {
    throw createError({
      statusCode: 400,
      statusMessage: '应用标识无效',
    })
  }

  setResponseHeader(event, 'Cache-Control', 'no-store')
  const resolver = createCloudbaseCatalogResolver()
  const view = await resolver.resolveCatalog({ surface: 'public_market' }, null)
  const found = view.apps.find(app => app._id === key || app.marketShortName === key.toLowerCase())
  const app = found ? catalogAppViewToRecord(found) : null
  if (!app) {
    throw createError({
      statusCode: 404,
      statusMessage: '应用不存在',
      data: { code: 'APP_UNAVAILABLE', reasonCode: await publicAppUnavailableReason(key) },
    })
  }

  return { app }
})
