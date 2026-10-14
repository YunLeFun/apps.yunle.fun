import type { AppRecord } from './app'

export type WorkshopJoinPolicy = 'approval' | 'open' | 'closed'
export type WorkshopStatus = 'active' | 'disabled'
export type WorkshopMembershipStatus = 'pending' | 'active' | 'rejected' | 'left' | 'removed' | 'blocked'
export type WorkshopAccess = 'anonymous' | 'none' | 'pending' | 'active' | 'owner' | 'blocked'

export interface WorkshopPublicInfo {
  _id: string
  ownerName: string
  ownerAvatar?: string
  name: string
  description?: string
  joinPolicy: WorkshopJoinPolicy
  status: WorkshopStatus
}

export interface WorkshopView {
  surface: 'workshop'
  access: WorkshopAccess
  workshop: WorkshopPublicInfo
  apps: AppRecord[]
}

export interface WorkshopMembership {
  workshopId: string
  userUid: string
  userName?: string
  userAvatar?: string
  status: WorkshopMembershipStatus
  requestedAt?: number
  joinedAt?: number
  updatedAt: number
}

export interface WorkshopManagementView {
  workshop: WorkshopPublicInfo & {
    ownerUid: string
  }
  pending: WorkshopMembership[]
  guests: WorkshopMembership[]
  blocked: WorkshopMembership[]
}

export interface JoinWorkshopResult {
  status: WorkshopMembershipStatus
  joined: boolean
}
