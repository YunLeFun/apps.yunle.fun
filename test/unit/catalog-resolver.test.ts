import { describe, expect, it, vi } from 'vitest'
import { createCatalogResolver } from '../../server/domain/catalog'
import {
  catalogAppViewToRecord,
  createCloudbaseCatalogDataSource,
} from '../../server/domain/catalog/cloudbase'

describe('catalogResolver', () => {
  it('projects access and release metadata from an approved revision', async () => {
    const get = vi.fn(async () => ({
      data: [{
        _id: 'revision-approved',
        appId: 'app-1',
        revision: 1,
        snapshot: {
          name: '星纸',
          slug: 'paper-star',
          githubRepo: 'YunLeFun/play',
          accessMode: 'public',
          releaseStage: 'beta',
        },
      }],
    }))
    const limit = vi.fn(() => ({ get }))
    const where = vi.fn(() => ({ limit }))
    const collection = vi.fn(() => ({ where }))
    const source = createCloudbaseCatalogDataSource({
      command: { in: vi.fn(value => value) },
      collection,
    } as any)

    await expect(source.getRevisions(['revision-approved'])).resolves.toEqual([
      expect.objectContaining({
        snapshot: expect.objectContaining({
          githubRepo: 'YunLeFun/play',
          accessMode: 'public',
          releaseStage: 'beta',
        }),
      }),
    ])
  })

  it('keeps the approved repository link in the public record', () => {
    const record = catalogAppViewToRecord({
      _id: 'app-1',
      ownerUid: 'owner-1',
      ownerLogin: 'YunYouJun',
      revisionId: 'revision-approved',
      name: 'SMAP 星际导航',
      slug: 'smap',
      githubRepo: 'YunYouJun/smap',
      audience: 'public',
      publicationStatus: 'published',
      createdAt: 1,
      updatedAt: 2,
    })

    expect(record.githubRepo).toBe('YunYouJun/smap')
  })

  it('uses the approved revision for the public market instead of the owner current revision', async () => {
    const resolver = createCatalogResolver({
      async listApps() {
        return [{
          _id: 'app-1',
          ownerUid: 'owner-1',
          audience: 'public',
          publicationStatus: 'published',
          currentRevisionId: 'revision-current',
          createdAt: 1,
          updatedAt: 2,
        }]
      },
      async listPublicMarketListings() {
        return [{
          appId: 'app-1',
          status: 'listed',
          shortName: 'example',
          approvedRevisionId: 'revision-approved',
        }]
      },
      async getRevisions() {
        return [
          {
            _id: 'revision-approved',
            appId: 'app-1',
            revision: 1,
            snapshot: {
              name: '审核版本',
              slug: 'reviewed-app',
              websiteUrl: 'https://reviewed.example.com/',
              accessMode: 'login_required',
              releaseStage: 'beta',
            },
          },
          {
            _id: 'revision-current',
            appId: 'app-1',
            revision: 2,
            snapshot: {
              name: '所有者最新版本',
              slug: 'reviewed-app',
              websiteUrl: 'https://current.example.com/',
            },
          },
        ]
      },
      async getWorkshop() {
        return null
      },
      async getMembership() {
        return null
      },
    })

    const view = await resolver.resolveCatalog({ surface: 'public_market' }, null)

    expect(view.apps).toEqual([
      expect.objectContaining({
        _id: 'app-1',
        name: '审核版本',
        websiteUrl: 'https://reviewed.example.com/',
        accessMode: 'login_required',
        releaseStage: 'beta',
      }),
    ])
  })

  it('shows only the owner current published public apps in a personal market', async () => {
    const resolver = createCatalogResolver({
      async listApps() {
        return [
          {
            _id: 'public-app',
            ownerUid: 'owner-1',
            audience: 'public',
            publicationStatus: 'published',
            currentRevisionId: 'revision-public',
            createdAt: 1,
            updatedAt: 3,
          },
          {
            _id: 'workshop-app',
            ownerUid: 'owner-1',
            audience: 'workshop',
            publicationStatus: 'published',
            currentRevisionId: 'revision-workshop',
            createdAt: 1,
            updatedAt: 2,
          },
          {
            _id: 'other-app',
            ownerUid: 'owner-2',
            audience: 'public',
            publicationStatus: 'published',
            currentRevisionId: 'revision-other',
            createdAt: 1,
            updatedAt: 1,
          },
        ]
      },
      async listPublicMarketListings() {
        return []
      },
      async getRevisions() {
        return [
          {
            _id: 'revision-public',
            appId: 'public-app',
            revision: 2,
            snapshot: {
              name: '个人市场应用',
              slug: 'personal-app',
              websiteUrl: 'https://personal.example.com/',
            },
          },
          {
            _id: 'revision-workshop',
            appId: 'workshop-app',
            revision: 1,
            snapshot: {
              name: '坊客专属应用',
              slug: 'workshop-app',
            },
          },
          {
            _id: 'revision-other',
            appId: 'other-app',
            revision: 1,
            snapshot: {
              name: '其他人的应用',
              slug: 'other-app',
            },
          },
        ]
      },
      async getWorkshop() {
        return null
      },
      async getMembership() {
        return null
      },
    })

    const view = await resolver.resolveCatalog({
      surface: 'personal_market',
      ownerUid: 'owner-1',
    }, null)

    expect(view.apps.map(app => app._id)).toEqual(['public-app'])
    expect(view.apps[0]?.revisionId).toBe('revision-public')
  })

  it('returns only semi-visible workshop information to a non-member', async () => {
    const resolver = createCatalogResolver({
      async listApps() {
        return [{
          _id: 'workshop-app',
          ownerUid: 'owner-1',
          audience: 'workshop',
          publicationStatus: 'published',
          currentRevisionId: 'revision-workshop',
          createdAt: 1,
          updatedAt: 1,
        }]
      },
      async listPublicMarketListings() {
        return []
      },
      async getRevisions() {
        return [{
          _id: 'revision-workshop',
          appId: 'workshop-app',
          revision: 1,
          snapshot: {
            name: '不能泄露的应用',
            slug: 'secret-app',
            websiteUrl: 'https://secret.example.com/',
          },
        }]
      },
      async getWorkshop() {
        return {
          _id: '7KM2QX',
          ownerUid: 'owner-1',
          ownerName: '云游君',
          ownerAvatar: 'https://example.com/avatar.png',
          name: '云游君的个人工坊',
          description: '仅向坊客开放',
          joinPolicy: 'approval',
          status: 'active',
          createdAt: 1,
          updatedAt: 1,
        }
      },
      async getMembership() {
        return null
      },
    })

    const view = await resolver.resolveCatalog({
      surface: 'workshop',
      workshopId: '7KM2QX',
    }, { uid: 'visitor-1' })

    expect(view).toMatchObject({
      surface: 'workshop',
      access: 'none',
      workshop: {
        _id: '7KM2QX',
        ownerName: '云游君',
        name: '云游君的个人工坊',
        description: '仅向坊客开放',
        joinPolicy: 'approval',
      },
      apps: [],
    })
    expect(JSON.stringify(view)).not.toContain('secret.example.com')
  })

  it('shows published public and workshop apps to an active guest but never owner apps', async () => {
    const resolver = createCatalogResolver({
      async listApps() {
        return [
          {
            _id: 'public-app',
            ownerUid: 'owner-1',
            audience: 'public',
            publicationStatus: 'published',
            currentRevisionId: 'revision-public',
            createdAt: 1,
            updatedAt: 3,
          },
          {
            _id: 'workshop-app',
            ownerUid: 'owner-1',
            audience: 'workshop',
            publicationStatus: 'published',
            currentRevisionId: 'revision-workshop',
            createdAt: 1,
            updatedAt: 2,
          },
          {
            _id: 'owner-app',
            ownerUid: 'owner-1',
            audience: 'owner',
            publicationStatus: 'published',
            currentRevisionId: 'revision-owner',
            createdAt: 1,
            updatedAt: 1,
          },
        ]
      },
      async listPublicMarketListings() {
        return []
      },
      async getRevisions() {
        return [
          {
            _id: 'revision-public',
            appId: 'public-app',
            revision: 1,
            snapshot: { name: '公开应用', slug: 'public-app' },
          },
          {
            _id: 'revision-workshop',
            appId: 'workshop-app',
            revision: 1,
            snapshot: { name: '坊客专属应用', slug: 'workshop-app' },
          },
          {
            _id: 'revision-owner',
            appId: 'owner-app',
            revision: 1,
            snapshot: { name: '仅坊主应用', slug: 'owner-app' },
          },
        ]
      },
      async getWorkshop() {
        return {
          _id: '7KM2QX',
          ownerUid: 'owner-1',
          ownerName: '云游君',
          name: '云游君的个人工坊',
          joinPolicy: 'approval',
          status: 'active',
          createdAt: 1,
          updatedAt: 1,
        }
      },
      async getMembership() {
        return {
          workshopId: '7KM2QX',
          userUid: 'guest-1',
          status: 'active',
          joinedAt: 2,
          updatedAt: 2,
        }
      },
    })

    const view = await resolver.resolveCatalog({
      surface: 'workshop',
      workshopId: '7KM2QX',
    }, { uid: 'guest-1' })

    expect(view.access).toBe('active')
    expect(view.apps.map(app => app._id)).toEqual(['public-app', 'workshop-app'])
  })
})
