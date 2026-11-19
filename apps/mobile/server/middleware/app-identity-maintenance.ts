import { requireAppIdentityMigration } from '../utils/app-write-version'
import { useCloudbaseAdmin } from '../utils/cloudbase-admin'

export default defineEventHandler(async (event) => {
  const path = event.path.split('?')[0] || ''
  if (!['POST', 'PUT', 'PATCH', 'DELETE'].includes(event.method) || !(/^\/api\/apps\/[^/]+(?:\/(?:submissions|public-market))?$/.test(path)))
    return
  await requireAppIdentityMigration(useCloudbaseAdmin().db)
})
