import { createError, getRequestHeader, getRouterParam, setResponseHeader } from 'h3'
import { CatalogNotFoundError } from '../../domain/catalog'
import {
  catalogAppViewToRecord,
  createCloudbaseCatalogResolver,
} from '../../domain/catalog/cloudbase'
import { requireRegisteredCloudbaseUser } from '../../utils/cloudbase-auth'

const WORKSHOP_ID_PATTERN = /^[2-9A-HJKMNP-Z]{6}$/

export default defineEventHandler(async (event) => {
  const workshopId = getRouterParam(event, 'id')?.trim().toUpperCase() || ''
  if (!WORKSHOP_ID_PATTERN.test(workshopId))
    throw createError({ statusCode: 404, message: '个人工坊不存在' })

  const user = getRequestHeader(event, 'authorization') !== undefined
    ? await requireRegisteredCloudbaseUser(event)
    : null
  const resolver = createCloudbaseCatalogResolver()
  try {
    const view = await resolver.resolveCatalog({
      surface: 'workshop',
      workshopId,
    }, user ? { uid: user.uid } : null)
    setResponseHeader(event, 'Cache-Control', 'private, no-store')
    return {
      ...view,
      apps: view.apps.map(catalogAppViewToRecord),
    }
  }
  catch (error: unknown) {
    if (error instanceof CatalogNotFoundError)
      throw createError({ statusCode: 404, message: error.message })
    throw error
  }
})
