import { getQuery } from 'h3'
import { useCloudbaseAdmin } from '../../../utils/cloudbase-admin'
import { requireDiagnosticAdmin } from '../../../utils/diagnostic-admin'
import { listActiveDiagnosticLogUploads } from '../../../utils/diagnostic-log-admin-service'
import { validateDiagnosticLogAdminQuery } from '../../../utils/diagnostic-logs'

export default defineEventHandler(async (event) => {
  await requireDiagnosticAdmin(event)
  const input = validateDiagnosticLogAdminQuery(getQuery(event))
  const { db } = useCloudbaseAdmin()
  const uploads = await listActiveDiagnosticLogUploads(db, input)

  return {
    code: 0,
    data: {
      uploads,
    },
  }
})
