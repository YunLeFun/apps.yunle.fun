/** Personal workshop membership state Module. */
import type {
  CatalogPrincipal,
  PersonalWorkshop,
  WorkshopMembership,
  WorkshopMembershipStatus,
} from '../catalog'

export interface WorkshopMembershipEvent {
  workshopId: string
  action:
    | 'membership.requested'
    | 'membership.joined'
    | 'membership.approved'
    | 'membership.rejected'
    | 'membership.left'
    | 'membership.removed'
    | 'membership.blocked'
    | 'membership.unblocked'
  actorUid: string
  targetUid: string
  createdAt: number
}

export interface WorkshopMembershipDataSource {
  getWorkshop: (workshopId: string) => Promise<PersonalWorkshop | null>
  getMembership: (workshopId: string, userUid: string) => Promise<WorkshopMembership | null>
  commitMembershipChange: (
    membership: WorkshopMembership,
    event: WorkshopMembershipEvent,
  ) => Promise<void>
}

export interface WorkshopMembershipClock {
  now: () => number
}

export interface JoinWorkshopResult {
  status: WorkshopMembershipStatus
  joined: boolean
}

export interface WorkshopMembershipModule {
  join: (workshopId: string, principal: CatalogPrincipal) => Promise<JoinWorkshopResult>
  decide: (
    workshopId: string,
    targetUid: string,
    decision: 'approve' | 'reject' | 'remove' | 'block' | 'unblock',
    principal: CatalogPrincipal,
  ) => Promise<WorkshopMembership>
  leave: (workshopId: string, principal: CatalogPrincipal) => Promise<WorkshopMembership>
}

export function createWorkshopMembershipModule(
  source: WorkshopMembershipDataSource,
  clock: WorkshopMembershipClock = { now: () => Date.now() },
): WorkshopMembershipModule {
  return {
    async join(workshopId, principal) {
      const workshop = await source.getWorkshop(workshopId)
      if (!workshop)
        throw new WorkshopMembershipError('WORKSHOP_NOT_FOUND', '个人工坊不存在')
      if (workshop.status === 'disabled')
        throw new WorkshopMembershipError('WORKSHOP_DISABLED', '个人工坊已停用')
      const existing = await source.getMembership(workshopId, principal.uid)
      if (existing?.status === 'active') {
        return {
          status: 'active',
          joined: true,
        }
      }
      if (existing?.status === 'pending' && workshop.joinPolicy === 'approval') {
        return {
          status: 'pending',
          joined: false,
        }
      }
      if (existing?.status === 'blocked')
        throw new WorkshopMembershipError('WORKSHOP_MEMBER_BLOCKED', '你暂时无法申请加入此个人工坊')
      if (workshop.joinPolicy === 'closed')
        throw new WorkshopMembershipError('WORKSHOP_JOIN_CLOSED', '个人工坊暂不接受新坊客')

      const now = clock.now()
      if (existing
        && (existing.status === 'rejected' || existing.status === 'left' || existing.status === 'removed')
        && now - existing.updatedAt < 60_000) {
        throw new WorkshopMembershipError('WORKSHOP_JOIN_RATE_LIMITED', '申请过于频繁，请一分钟后再试')
      }
      const openJoining = workshop.joinPolicy === 'open'
      const next: WorkshopMembership = {
        workshopId,
        userUid: principal.uid,
        ...(principal.name ? { userName: principal.name } : {}),
        ...(principal.avatar ? { userAvatar: principal.avatar } : {}),
        status: openJoining ? 'active' : 'pending',
        requestedAt: now,
        ...(openJoining ? { joinedAt: now } : {}),
        updatedAt: now,
      }
      await source.commitMembershipChange(next, {
        workshopId,
        action: openJoining ? 'membership.joined' : 'membership.requested',
        actorUid: principal.uid,
        targetUid: principal.uid,
        createdAt: now,
      })
      return {
        status: next.status,
        joined: openJoining,
      }
    },
    async decide(workshopId, targetUid, decision, principal) {
      const workshop = await source.getWorkshop(workshopId)
      if (!workshop)
        throw new WorkshopMembershipError('WORKSHOP_NOT_FOUND', '个人工坊不存在')
      if (workshop.ownerUid !== principal.uid)
        throw new WorkshopMembershipError('WORKSHOP_OWNER_REQUIRED', '只有坊主可以处理加入申请')

      const existing = await source.getMembership(workshopId, targetUid)
      if (!existing)
        throw new WorkshopMembershipError('WORKSHOP_MEMBERSHIP_NOT_FOUND', '坊客关系不存在')
      if ((decision === 'approve' || decision === 'reject') && existing.status !== 'pending')
        throw new WorkshopMembershipError('WORKSHOP_APPLICATION_NOT_PENDING', '加入申请已处理或不存在')
      if (decision === 'unblock' && existing.status !== 'blocked')
        throw new WorkshopMembershipError('WORKSHOP_MEMBER_NOT_BLOCKED', '该用户未被拉黑')

      const now = clock.now()
      const nextStatus = decisionStatus(decision)
      const next: WorkshopMembership = {
        ...existing,
        status: nextStatus,
        ...(decision === 'approve' ? { joinedAt: now } : {}),
        updatedAt: now,
      }
      await source.commitMembershipChange(next, {
        workshopId,
        action: decisionEvent(decision),
        actorUid: principal.uid,
        targetUid,
        createdAt: now,
      })
      return next
    },
    async leave(workshopId, principal) {
      const workshop = await source.getWorkshop(workshopId)
      if (!workshop)
        throw new WorkshopMembershipError('WORKSHOP_NOT_FOUND', '个人工坊不存在')
      const existing = await source.getMembership(workshopId, principal.uid)
      if (!existing || (existing.status !== 'active' && existing.status !== 'pending'))
        throw new WorkshopMembershipError('WORKSHOP_MEMBERSHIP_NOT_ACTIVE', '你尚未加入此个人工坊')

      const now = clock.now()
      const next: WorkshopMembership = {
        ...existing,
        status: 'left',
        updatedAt: now,
      }
      await source.commitMembershipChange(next, {
        workshopId,
        action: 'membership.left',
        actorUid: principal.uid,
        targetUid: principal.uid,
        createdAt: now,
      })
      return next
    },
  }
}

function decisionStatus(
  decision: 'approve' | 'reject' | 'remove' | 'block' | 'unblock',
): WorkshopMembershipStatus {
  switch (decision) {
    case 'approve': return 'active'
    case 'reject': return 'rejected'
    case 'remove': return 'removed'
    case 'block': return 'blocked'
    case 'unblock': return 'removed'
  }
}

function decisionEvent(
  decision: 'approve' | 'reject' | 'remove' | 'block' | 'unblock',
): WorkshopMembershipEvent['action'] {
  switch (decision) {
    case 'approve': return 'membership.approved'
    case 'reject': return 'membership.rejected'
    case 'remove': return 'membership.removed'
    case 'block': return 'membership.blocked'
    case 'unblock': return 'membership.unblocked'
  }
}

export class WorkshopMembershipError extends Error {
  constructor(
    public readonly code: string,
    message: string,
  ) {
    super(message)
    this.name = 'WorkshopMembershipError'
  }
}
