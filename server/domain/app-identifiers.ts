import { createHash } from 'node:crypto'

export const APP_IDENTIFIERS_COLLECTION = 'app_identifiers'
const RESERVED = new Set(['admin', 'api', 'apps', 'app', 'new', 'edit', 'login', 'logout', 'signup', 'register', 'settings', 'account', 'support', 'help', 'market', 'workshop', 'public', 'official', 'yunlefun', 'u'])

export function normalizeMarketShortName(value: unknown): string {
  const name = typeof value === 'string' ? value.trim().toLowerCase() : ''
  if (!/^[a-z][a-z0-9-]{1,49}$/.test(name) || RESERVED.has(name)) {
    throw new AppIdentifierError(400, '市场短名须为 2–50 位小写字母、数字或连字符，以字母开头，且不能使用系统保留名称', 'MARKET_SHORT_NAME_INVALID')
  }
  return name
}

export function identifierKey(kind: 'namespace' | 'market', name: string, ownerUid = ''): string {
  return `${kind}_${createHash('sha256').update(JSON.stringify([ownerUid, name.toLowerCase()])).digest('hex')}`
}

interface IdentifierRecord { appId: string }
interface IdentifierTransaction {
  collection: (name: string) => {
    doc: (id: string) => {
      get: () => Promise<{ data?: unknown }>
      set: (data: Record<string, unknown>) => Promise<unknown>
    }
  }
}

/** Must run inside the same database transaction as the app/listing write. Never release on delisting. */
export async function claimAppIdentifier(transaction: IdentifierTransaction, kind: 'namespace' | 'market', name: string, appId: string, ownerUid = '') {
  const ref = transaction.collection(APP_IDENTIFIERS_COLLECTION).doc(identifierKey(kind, name, ownerUid))
  const { data } = await ref.get()
  const existing = (Array.isArray(data) ? data[0] : data) as IdentifierRecord | undefined
  if (existing && existing.appId !== appId) {
    throw new AppIdentifierError(409, kind === 'market' ? '市场短名已被占用，请选择其他短名' : '你的命名空间内已存在此 slug', kind === 'market' ? 'MARKET_SHORT_NAME_TAKEN' : 'APP_SLUG_TAKEN')
  }
  if (!existing)
    await ref.set({ kind, name: name.toLowerCase(), appId, ownerUid, createdAt: Date.now() })
}

export class AppIdentifierError extends Error {
  readonly data: { code: string }

  constructor(readonly statusCode: number, message: string, code: string) {
    super(message)
    this.name = 'AppIdentifierError'
    this.data = { code }
  }
}
