import { describe, expect, it } from 'vitest'
import {
  AppStoreConnectClient,
  maskEmail,
  matchEligibleTesters,
  parseArgs,
  publishTestFlight,
  selectBuild,
} from '../../scripts/ios-testflight-publish.mjs'

function build(version: string, overrides: Record<string, unknown> = {}) {
  return {
    id: `build-${version}`,
    type: 'builds',
    attributes: {
      version,
      uploadedDate: new Date(Date.UTC(2026, 0, 1, 0, 0, Number(version))).toISOString(),
      expired: false,
      processingState: 'VALID',
      buildAudienceType: 'INTERNAL_ONLY',
      ...overrides,
    },
  }
}

describe('ios-testflight-publish CLI', () => {
  it('does not invite testers unless explicitly requested', () => {
    expect(parseArgs([])).toMatchObject({
      inviteAllInternalUsers: false,
      testerEmails: [],
    })
  })

  it('parses build, tester and dry-run options', () => {
    expect(parseArgs([
      '--',
      '--build',
      '122',
      '--version',
      '0.2.0',
      '--tester-email',
      'tester@example.com',
      '--invite-all-internal-users',
      '--dry-run',
    ])).toEqual({
      buildNumber: '122',
      dryRun: true,
      help: false,
      inviteAllInternalUsers: true,
      testerEmails: ['tester@example.com'],
      marketingVersion: '0.2.0',
    })
  })

  it('rejects unknown or incomplete options', () => {
    expect(() => parseArgs(['--build'])).toThrow('--build 需要一个值')
    expect(() => parseArgs(['--version'])).toThrow('--version 需要一个值')
    expect(() => parseArgs(['--unknown'])).toThrow('未知参数')
  })
})

describe('testflight build selection', () => {
  it('selects the newest valid unexpired build', () => {
    expect(selectBuild([
      build('121'),
      build('122'),
      build('123', { processingState: 'PROCESSING' }),
    ], undefined).attributes.version).toBe('122')
  })

  it('does not publish invalid or expired requested builds', () => {
    expect(() => selectBuild([
      build('122', { processingState: 'INVALID' }),
    ], '122')).toThrow('构建尚不可发布')
    expect(() => selectBuild([
      build('122', { expired: true }),
    ], '122')).toThrow('构建尚不可发布')
  })

  it('rejects an ambiguous build number instead of selecting a different marketing version', () => {
    expect(() => selectBuild([build('1'), build('1')], '1')).toThrow('--version')
  })
})

describe('app Store Connect API safety', () => {
  it('masks tester emails in failed request paths and response details', async () => {
    const client = new AppStoreConnectClient({
      token: 'test-token',
      fetchImpl: async () => new Response(JSON.stringify({
        errors: [{ code: 'INVALID', detail: 'tester@example.com cannot be invited' }],
      }), { status: 400 }),
    })

    const error = await client
      .request('/v1/betaTesters?filter[email]=tester%40example.com')
      .catch(reason => reason as Error)

    expect(error.message).not.toContain('tester@example.com')
    expect(error.message).not.toContain('tester%40example.com')
    expect(error.message).toContain('te***@example.com')
  })

  it('follows App Store Connect pagination links until all resources are loaded', async () => {
    const client = new AppStoreConnectClient({
      token: 'test-token',
      fetchImpl: async (url) => {
        const isSecondPage = String(url).includes('cursor=page-2')
        return new Response(JSON.stringify(isSecondPage
          ? { data: [{ id: 'tester-2' }], links: {} }
          : {
              data: [{ id: 'tester-1' }],
              links: {
                next: 'https://api.appstoreconnect.apple.com/v1/betaTesters?cursor=page-2',
              },
            }))
      },
    })

    const resources = await client.requestAll('/v1/betaTesters?limit=200')
    expect(resources).toEqual([{ id: 'tester-1' }, { id: 'tester-2' }])
  })
})

describe('internal tester safety', () => {
  const eligibleUsers = [
    { id: 'user-1', attributes: { username: 'first@example.com', roles: ['DEVELOPER'] } },
    { id: 'user-2', attributes: { username: 'second@example.com', roles: ['MARKETING'] } },
    { id: 'user-3', attributes: { username: 'sales@example.com', roles: ['SALES'] } },
  ]
  const betaTesters = [
    { id: 'tester-1', attributes: { email: 'first@example.com' } },
    { id: 'tester-2', attributes: { email: 'second@example.com' } },
    { id: 'tester-3', attributes: { email: 'sales@example.com' } },
  ]

  it('matches only explicitly requested testers by default', () => {
    expect(matchEligibleTesters({
      betaTesters,
      eligibleUsers,
      requestedEmails: ['second@example.com'],
      inviteAll: false,
    }).map(target => target.tester?.id)).toEqual(['tester-2'])
  })

  it('requires an explicit flag before returning all eligible testers', () => {
    expect(matchEligibleTesters({
      betaTesters,
      eligibleUsers,
      requestedEmails: [],
      inviteAll: false,
    })).toEqual([])
    expect(matchEligibleTesters({
      betaTesters,
      eligibleUsers,
      requestedEmails: [],
      inviteAll: true,
    })).toHaveLength(2)
  })

  it('rejects App Store Connect roles that cannot join internal testing', () => {
    expect(() => matchEligibleTesters({
      betaTesters,
      eligibleUsers,
      requestedEmails: ['sales@example.com'],
      inviteAll: false,
    })).toThrow('sa***@example.com')
  })

  it('plans creation when an eligible internal user has no beta tester record', () => {
    expect(matchEligibleTesters({
      betaTesters: [],
      eligibleUsers,
      requestedEmails: ['first@example.com'],
      inviteAll: false,
    })).toMatchObject([{
      email: 'first@example.com',
      tester: null,
      user: { id: 'user-1' },
    }])
  })

  it('masks email addresses in errors and logs', () => {
    expect(maskEmail('tester@example.com')).toBe('te***@example.com')
    expect(() => matchEligibleTesters({
      betaTesters,
      eligibleUsers,
      requestedEmails: ['unknown@example.com'],
      inviteAll: false,
    })).toThrow('un***@example.com')
  })
})

describe('testFlight publication', () => {
  it('pins the requested iOS marketing version when build numbers are reused', async () => {
    const builds = ['old-ios', 'target-ios', 'same-version-macos'].map(id => ({
      ...build('1'),
      id,
      relationships: { preReleaseVersion: { data: { id: `version-${id}` } } },
    }))
    const client = {
      async request(path: string, options: Record<string, any> = {}) {
        expect(options.method ?? 'GET').toBe('GET')
        if (path.startsWith('/v1/apps?'))
          return { data: [{ id: 'app-1', attributes: { name: '云乐坊', bundleId: 'fun.yunle.apps' } }] }
        if (path.startsWith('/v1/builds?')) {
          expect(new URL(path, 'https://api.appstoreconnect.apple.com').searchParams.get('include')).toBe('preReleaseVersion')
          return {
            data: builds,
            included: builds.map(item => ({
              id: `version-${item.id}`,
              type: 'preReleaseVersions',
              attributes: {
                version: item.id === 'old-ios' ? '0.1.0' : '0.2.0',
                platform: item.id === 'same-version-macos' ? 'MAC_OS' : 'IOS',
              },
            })),
          }
        }
        if (path.includes('/betaGroups?') || path.includes('/betaAppLocalizations?') || path.includes('/betaBuildLocalizations?'))
          return { data: [] }
        throw new Error(`Unexpected request: ${path}`)
      },
    }
    const result = await publishTestFlight({
      client,
      config: { bundleId: 'fun.yunle.apps', buildNumber: '1', marketingVersion: '0.2.0', dryRun: true },
      log: () => {},
    })
    expect(result.build.id).toBe('target-ios')
  })

  it('rejects a public build before making any publication changes', async () => {
    const client = {
      async request(path: string) {
        if (path.startsWith('/v1/apps?'))
          return { data: [{ id: 'app-1', attributes: { name: '云乐坊' } }] }
        if (path.startsWith('/v1/builds?'))
          return { data: [build('1', { buildAudienceType: 'APP_STORE_ELIGIBLE' })] }
        throw new Error(`Unexpected request: ${path}`)
      },
    }
    await expect(publishTestFlight({ client, config: { bundleId: 'fun.yunle.apps', buildNumber: '1' } }))
      .rejects
      .toThrow('INTERNAL_ONLY')
  })

  it('creates and assigns a missing beta tester for an eligible internal user', async () => {
    const group = {
      id: 'group-1',
      attributes: {
        name: '云乐坊内测组',
        isInternalGroup: true,
        hasAccessToAllBuilds: true,
        feedbackEnabled: true,
      },
    }
    const selectedBuild = build('122', { usesNonExemptEncryption: false })
    const createdTesters: Array<Record<string, any>> = []
    const client = {
      async request(path: string, options: Record<string, any> = {}) {
        if (path.startsWith('/v1/apps?'))
          return { data: [{ id: 'app-1', attributes: { name: '云乐坊', bundleId: 'fun.yunle.apps' } }] }
        if (path.startsWith('/v1/builds?'))
          return { data: [selectedBuild] }
        if (path.startsWith('/v1/apps/app-1/betaGroups?'))
          return { data: [group] }
        if (path === '/v1/betaGroups/group-1/relationships/builds?limit=200')
          return { data: [selectedBuild] }
        if (path === '/v1/betaTesters' && options.method === 'POST') {
          const tester = {
            id: 'tester-created',
            attributes: options.body.data.attributes,
          }
          createdTesters.push(tester)
          return { data: tester }
        }
        if (path.startsWith('/v1/apps/app-1/betaAppLocalizations?')) {
          return {
            data: [{
              id: 'app-localization-1',
              attributes: {
                locale: 'zh-Hans',
                description: '测试描述',
                feedbackEmail: 'feedback@example.com',
                marketingUrl: 'https://example.com',
                privacyPolicyUrl: 'https://example.com/privacy',
              },
            }],
          }
        }
        if (path.startsWith('/v1/builds/build-122/betaBuildLocalizations?')) {
          return {
            data: [{
              id: 'build-localization-1',
              attributes: { locale: 'zh-Hans', whatsNew: '测试重点' },
            }],
          }
        }
        if (path === '/v1/builds/build-122/buildBetaDetail') {
          return {
            data: { attributes: { internalBuildState: 'IN_BETA_TESTING', externalBuildState: 'NOT_APPLICABLE' } },
          }
        }
        throw new Error(`Unexpected request: ${options.method ?? 'GET'} ${path}`)
      },
      async requestAll(path: string) {
        if (path.startsWith('/v1/users?')) {
          return [{
            id: 'user-1',
            attributes: {
              username: 'new@example.com',
              firstName: 'New',
              lastName: 'Tester',
              roles: ['DEVELOPER'],
              allAppsVisible: true,
            },
          }]
        }
        if (path.startsWith('/v1/betaTesters?'))
          return []
        if (path === '/v1/betaGroups/group-1/relationships/betaTesters?limit=200')
          return createdTesters
        if (path === '/v1/betaGroups/group-1/relationships/builds?limit=200')
          return [selectedBuild]
        throw new Error(`Unexpected paginated request: ${path}`)
      },
    }

    const result = await publishTestFlight({
      client,
      config: {
        betaDescription: '测试描述',
        buildNumber: '122',
        bundleId: 'fun.yunle.apps',
        dryRun: false,
        feedbackEmail: 'feedback@example.com',
        groupName: '云乐坊内测组',
        inviteAllInternalUsers: false,
        locale: 'zh-Hans',
        marketingUrl: 'https://example.com',
        privacyPolicyUrl: 'https://example.com/privacy',
        testerEmails: ['new@example.com'],
        whatsNew: '测试重点',
      },
      log: () => {},
    })

    expect(createdTesters).toMatchObject([{
      attributes: { email: 'new@example.com' },
    }])
    expect(result.testerCount).toBe(1)
  })
})
