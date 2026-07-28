import { setResponseHeader } from 'h3'
import {
  catalogAppViewToRecord,
  createCloudbaseCatalogResolver,
} from '../../../domain/catalog/cloudbase'

export default defineEventHandler(async (event) => {
  const resolver = createCloudbaseCatalogResolver()
  const view = await resolver.resolveCatalog({ surface: 'public_market' }, null)
  const items = view.apps.map(catalogAppViewToRecord)
  setResponseHeader(event, 'Cache-Control', 'public, max-age=60, stale-while-revalidate=300')
  return { items }
})
