import { setResponseHeader } from 'h3'
import { listPublicApps } from '../../../utils/public-apps'

export default defineEventHandler(async (event) => {
  const items = await listPublicApps()
  setResponseHeader(event, 'Cache-Control', 'public, max-age=60, stale-while-revalidate=300')
  return { items }
})
