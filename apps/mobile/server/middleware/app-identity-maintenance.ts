import { useCloudbaseAdmin } from '../utils/cloudbase-admin'

export default defineEventHandler(async (event) => {
  const path = event.path.split('?')[0] || ''
  if (!['POST', 'PUT', 'PATCH', 'DELETE'].includes(event.method) || !(/^\/api\/apps\/[^/]+(?:\/(?:submissions|public-market))?$/.test(path)))
    return
  const db = useCloudbaseAdmin().db
  const { data } = await db.collection('app_identifiers').doc('migration_v2').get()
  const gate = (Array.isArray(data) ? data[0] : data) as { ready?: boolean } | undefined
  if (gate?.ready !== true)
    throw createError({ statusCode: 503, message: '应用管理正在升级，请稍后重试', data: { code: 'APP_IDENTITY_MIGRATION' } })
})
