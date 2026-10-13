import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import {
  appNameConflict,
  isDuplicateKeyError,
  normalizeAppNameKey,
} from '../../server/domain/app-name'

describe('application name uniqueness', () => {
  it('normalizes compatibility characters, whitespace, punctuation, and case', () => {
    expect(normalizeAppNameKey('  请给我钱！  ')).toBe('请给我钱!')
    expect(normalizeAppNameKey('ＣＯＯＫ　Helper')).toBe('cook helper')
    expect(normalizeAppNameKey('今天   来做菜')).toBe('今天 来做菜')
  })

  it('excludes the application being edited from conflicts', () => {
    const rows = [{ _id: 'app-a', nameKey: '云风扇' }]
    expect(appNameConflict(rows, 'app-a')).toBeUndefined()
    expect(appNameConflict(rows, 'app-b')?._id).toBe('app-a')
  })

  it('recognizes duplicate-key failures for the final concurrency guard', () => {
    expect(isDuplicateKeyError({ code: 11000, message: 'E11000 duplicate key error' })).toBe(true)
    expect(isDuplicateKeyError(new Error('duplicate key for idx_name_key_unique'))).toBe(true)
    expect(isDuplicateKeyError(new Error('timeout'))).toBe(false)
  })

  it('guards create, edit, and public-market submission paths', () => {
    const source = readFileSync(
      new URL('../../server/utils/app-submissions.ts', import.meta.url),
      'utf8',
    )
    expect(source).toMatch(/createAppSubmission[\s\S]*assertAppNameAvailable/)
    expect(source).toMatch(/updateAppSubmission[\s\S]*assertAppNameAvailable/)
    expect(source).toMatch(/submitOwnedAppToPublicMarket[\s\S]*assertAppNameAvailable/)
    expect(source).toContain('APP_NAME_TAKEN')
  })

  it('only excludes an edited application owned by the signed-in user', () => {
    const source = readFileSync(
      new URL('../../server/api/apps/name.post.ts', import.meta.url),
      'utf8',
    )
    expect(source).toContain('requireVerifiedCloudbaseUser(event)')
    expect(source).toContain('app?.ownerUid === user.uid')
    expect(source).toContain('name.length > 50')
    expect(source).toContain('checkAppNameAvailability(name, excludeAppId)')
  })
})
