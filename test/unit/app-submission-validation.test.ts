import { describe, expect, it } from 'vitest'
import {
  isYunLeFunFirstPartyHostname,
  normalizeSubmissionInput,
} from '../../server/utils/app-submission-validation'

const base = {
  kind: 'first_party',
  name: 'CMS',
  slug: 'cms',
  websiteUrl: 'https://cms.yunle.fun',
  privacyPolicyUrl: 'https://cms.yunle.fun/privacy',
  supportUrl: 'https://support.yunle.fun',
}

describe('app submission validation', () => {
  it('accepts an exact yunle.fun subdomain and normalizes review-compatible fields', () => {
    const result = normalizeSubmissionInput({
      ...base,
      accessMode: 'invite_only',
      releaseStage: 'beta',
      githubRepo: 'YunLeFun/cms.yunle.fun',
    })
    expect(result).toMatchObject({
      kind: 'first_party',
      snapshot: {
        slug: 'cms',
        websiteUrl: 'https://cms.yunle.fun/',
        isPublic: true,
        accessMode: 'invite_only',
        releaseStage: 'beta',
        trustedHosts: ['cms.yunle.fun'],
      },
    })
  })

  it('does not confuse lookalike suffixes with first-party domains', () => {
    expect(isYunLeFunFirstPartyHostname('cms.yunle.fun')).toBe(true)
    expect(isYunLeFunFirstPartyHostname('yunle.fun.attacker.example')).toBe(false)
    expect(() => normalizeSubmissionInput({
      ...base,
      websiteUrl: 'https://yunle.fun.attacker.example',
    })).toThrow(/yunle\.fun/)
  })

  it('keeps third-party inputs schema-compatible but feature-gated', () => {
    const thirdParty = { ...base, kind: 'third_party', websiteUrl: 'https://example.com' }
    expect(() => normalizeSubmissionInput(thirdParty)).toThrow(/敬请期待/)
    expect(normalizeSubmissionInput(thirdParty, { thirdPartyEnabled: true }).kind).toBe('third_party')
  })

  it('requires HTTPS and a valid owner/repo repository', () => {
    expect(() => normalizeSubmissionInput({ ...base, websiteUrl: 'http://cms.yunle.fun' })).toThrow(/HTTPS/)
    expect(() => normalizeSubmissionInput({ ...base, githubRepo: 'not-a-repo' })).toThrow(/owner\/repo/)
  })

  it('accepts arbitrary HTTPS and static sites for workshop-only apps', () => {
    const result = normalizeSubmissionInput({
      ...base,
      audience: 'workshop',
      websiteUrl: 'https://static.example.com/tool/',
    })

    expect(result.snapshot).toMatchObject({
      audience: 'workshop',
      isPublic: false,
      websiteUrl: 'https://static.example.com/tool/',
    })
  })
})
