import { getQuery } from 'h3'
import { isAppSlugTaken } from '../../utils/app-submissions'

export default defineEventHandler(async (event) => {
  const slug = String(getQuery(event).slug || '').trim().toLowerCase()
  return { taken: await isAppSlugTaken(slug) }
})
