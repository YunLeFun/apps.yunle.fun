import type {
  PersonalWorkshop,
  WorkshopMembership,
} from '../../server/domain/catalog'
import { describe, expect, it } from 'vitest'
import { createWorkshopMembershipModule } from '../../server/domain/workshop-membership'

describe('workshopMembership', () => {
  it('creates a pending application when the workshop uses the default approval policy', async () => {
    const workshop: PersonalWorkshop = {
      _id: '7KM2QX',
      ownerUid: 'owner-1',
      ownerName: '云游君',
      name: '云游君的个人工坊',
      joinPolicy: 'approval',
      status: 'active',
      createdAt: 1,
      updatedAt: 1,
    }
    let saved: WorkshopMembership | null = null
    const membership = createWorkshopMembershipModule({
      async getWorkshop() {
        return workshop
      },
      async getMembership() {
        return null
      },
      async commitMembershipChange(value) {
        saved = value
      },
    }, {
      now: () => 1_750_000_000_000,
    })

    const result = await membership.join('7KM2QX', { uid: 'guest-1' })

    expect(result).toEqual({
      status: 'pending',
      joined: false,
    })
    expect(saved).toMatchObject({
      workshopId: '7KM2QX',
      userUid: 'guest-1',
      status: 'pending',
      requestedAt: 1_750_000_000_000,
      updatedAt: 1_750_000_000_000,
    })
  })

  it('joins immediately when the owner explicitly enables open joining', async () => {
    let saved: WorkshopMembership | null = null
    const membership = createWorkshopMembershipModule({
      async getWorkshop() {
        return {
          _id: '7KM2QX',
          ownerUid: 'owner-1',
          ownerName: '云游君',
          name: '云游君的个人工坊',
          joinPolicy: 'open',
          status: 'active',
          createdAt: 1,
          updatedAt: 1,
        }
      },
      async getMembership() {
        return null
      },
      async commitMembershipChange(value) {
        saved = value
      },
    }, {
      now: () => 1_750_000_000_000,
    })

    const result = await membership.join('7KM2QX', { uid: 'guest-1' })

    expect(result).toEqual({
      status: 'active',
      joined: true,
    })
    expect(saved).toMatchObject({
      status: 'active',
      requestedAt: 1_750_000_000_000,
      joinedAt: 1_750_000_000_000,
    })
  })

  it('rejects new applications when the workshop is closed', async () => {
    let saveCount = 0
    const membership = createWorkshopMembershipModule({
      async getWorkshop() {
        return {
          _id: '7KM2QX',
          ownerUid: 'owner-1',
          ownerName: '云游君',
          name: '云游君的个人工坊',
          joinPolicy: 'closed',
          status: 'active',
          createdAt: 1,
          updatedAt: 1,
        }
      },
      async getMembership() {
        return null
      },
      async commitMembershipChange() {
        saveCount += 1
      },
    })

    await expect(membership.join('7KM2QX', { uid: 'guest-1' }))
      .rejects
      .toMatchObject({ code: 'WORKSHOP_JOIN_CLOSED' })
    expect(saveCount).toBe(0)
  })

  it('never lets a blocked user rejoin, including under the open policy', async () => {
    let saveCount = 0
    const membership = createWorkshopMembershipModule({
      async getWorkshop() {
        return {
          _id: '7KM2QX',
          ownerUid: 'owner-1',
          ownerName: '云游君',
          name: '云游君的个人工坊',
          joinPolicy: 'open',
          status: 'active',
          createdAt: 1,
          updatedAt: 1,
        }
      },
      async getMembership() {
        return {
          workshopId: '7KM2QX',
          userUid: 'guest-1',
          status: 'blocked',
          updatedAt: 2,
        }
      },
      async commitMembershipChange() {
        saveCount += 1
      },
    })

    await expect(membership.join('7KM2QX', { uid: 'guest-1' }))
      .rejects
      .toMatchObject({ code: 'WORKSHOP_MEMBER_BLOCKED' })
    expect(saveCount).toBe(0)
  })

  it('keeps an existing active guest active after the owner changes the policy', async () => {
    let saveCount = 0
    const membership = createWorkshopMembershipModule({
      async getWorkshop() {
        return {
          _id: '7KM2QX',
          ownerUid: 'owner-1',
          ownerName: '云游君',
          name: '云游君的个人工坊',
          joinPolicy: 'closed',
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
      async commitMembershipChange() {
        saveCount += 1
      },
    })

    await expect(membership.join('7KM2QX', { uid: 'guest-1' })).resolves.toEqual({
      status: 'active',
      joined: true,
    })
    expect(saveCount).toBe(0)
  })

  it('deduplicates repeated pending applications without writing another audit event', async () => {
    let commitCount = 0
    const membership = createWorkshopMembershipModule({
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
          status: 'pending',
          requestedAt: 2,
          updatedAt: 2,
        }
      },
      async commitMembershipChange() {
        commitCount += 1
      },
    })

    await expect(membership.join('7KM2QX', { uid: 'guest-1' })).resolves.toEqual({
      status: 'pending',
      joined: false,
    })
    expect(commitCount).toBe(0)
  })

  it('rate limits rapid reapplications after a membership has ended', async () => {
    const membership = createWorkshopMembershipModule({
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
          status: 'rejected',
          updatedAt: 1_750_000_000_000,
        }
      },
      async commitMembershipChange() {
        throw new Error('rate-limited application must not be persisted')
      },
    }, {
      now: () => 1_750_000_030_000,
    })

    await expect(membership.join('7KM2QX', { uid: 'guest-1' }))
      .rejects
      .toMatchObject({ code: 'WORKSHOP_JOIN_RATE_LIMITED' })
  })

  it('does not accept new applications while the workshop is disabled', async () => {
    const membership = createWorkshopMembershipModule({
      async getWorkshop() {
        return {
          _id: '7KM2QX',
          ownerUid: 'owner-1',
          ownerName: '云游君',
          name: '云游君的个人工坊',
          joinPolicy: 'open',
          status: 'disabled',
          createdAt: 1,
          updatedAt: 1,
        }
      },
      async getMembership() {
        return null
      },
      async commitMembershipChange() {
        throw new Error('disabled workshop must not write a membership')
      },
    })

    await expect(membership.join('7KM2QX', { uid: 'guest-1' }))
      .rejects
      .toMatchObject({ code: 'WORKSHOP_DISABLED' })
  })

  it('lets only the workshop owner approve a pending application', async () => {
    let saved: WorkshopMembership | null = null
    const membership = createWorkshopMembershipModule({
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
          status: 'pending',
          requestedAt: 2,
          updatedAt: 2,
        }
      },
      async commitMembershipChange(value) {
        saved = value
      },
    }, {
      now: () => 1_750_000_000_000,
    })

    await membership.decide(
      '7KM2QX',
      'guest-1',
      'approve',
      { uid: 'owner-1' },
    )

    expect(saved).toMatchObject({
      status: 'active',
      joinedAt: 1_750_000_000_000,
      updatedAt: 1_750_000_000_000,
    })
    await expect(membership.decide(
      '7KM2QX',
      'guest-1',
      'approve',
      { uid: 'other-user' },
    )).rejects.toMatchObject({ code: 'WORKSHOP_OWNER_REQUIRED' })
  })
})
