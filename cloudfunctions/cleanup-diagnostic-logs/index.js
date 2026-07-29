const cloudbase = require('@cloudbase/node-sdk')

const app = cloudbase.init({
  env: cloudbase.SYMBOL_CURRENT_ENV,
})
const db = app.database()

async function cleanupExpiredDiagnosticLogs(now = Date.now()) {
  const result = await db
    .collection('diagnostic_log_uploads')
    .where({
      expiresAt: db.command.lt(now),
    })
    .remove()

  return {
    deleted: typeof result.deleted === 'number' ? result.deleted : 0,
    now,
  }
}

exports.main = async () => {
  const data = await cleanupExpiredDiagnosticLogs()

  console.log(JSON.stringify({ // eslint-disable-line no-console
    event: 'diagnostic.retention_cleanup',
    ...data,
  }))

  return {
    code: 0,
    data,
  }
}

exports.cleanupExpiredDiagnosticLogs = cleanupExpiredDiagnosticLogs
