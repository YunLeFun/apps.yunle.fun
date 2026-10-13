export interface AppNameRecord {
  _id: string
  nameKey?: string
}

export function normalizeAppNameKey(name: string): string {
  return name
    .normalize('NFKC')
    .trim()
    .replace(/\s+/gu, ' ')
    .toLocaleLowerCase('zh-CN')
}

export function appNameConflict<T extends AppNameRecord>(
  records: readonly T[],
  excludeAppId?: string,
): T | undefined {
  return records.find(record => record._id !== excludeAppId)
}

export function isDuplicateKeyError(error: unknown): boolean {
  if (!error || typeof error !== 'object')
    return false
  const value = error as { code?: unknown, message?: unknown }
  return value.code === 11000
    || (typeof value.message === 'string' && /E11000|duplicate key/i.test(value.message))
}
