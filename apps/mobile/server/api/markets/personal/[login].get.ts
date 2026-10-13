import { createError, getRouterParam, setResponseHeader } from 'h3'
import {
  catalogAppViewToRecord,
  createCloudbaseCatalogResolver,
  resolveOwnerUidByLogin,
} from '../../../domain/catalog/cloudbase'

const LOGIN_PATTERN = /^[\w.-]{1,64}$/

export default defineEventHandler(async (event) => {
  const login = getRouterParam(event, 'login')?.trim() || ''
  if (!LOGIN_PATTERN.test(login))
    throw createError({ statusCode: 400, message: '用户标识无效' })

  const ownerUid = await resolveOwnerUidByLogin(login)
  if (!ownerUid)
    throw createError({ statusCode: 404, message: '个人主页不存在' })

  const resolver = createCloudbaseCatalogResolver()
  const view = await resolver.resolveCatalog({
    surface: 'personal_market',
    ownerUid,
  }, null)
  setResponseHeader(event, 'Cache-Control', 'public, max-age=60, stale-while-revalidate=300')
  return {
    ownerLogin: login,
    items: view.apps.map(catalogAppViewToRecord),
  }
})
