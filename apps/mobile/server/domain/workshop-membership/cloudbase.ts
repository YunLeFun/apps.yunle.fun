import type { WorkshopMembershipDataSource } from '.'
/** CloudBase Adapter for the workshop membership Module. */
import type {
  CloudbaseAdminDb,
  CloudbaseTransaction,
} from '../../utils/cloudbase-admin'
import type {
  PersonalWorkshop,
  WorkshopMembership,
} from '../catalog'
import { randomUUID } from 'node:crypto'
import { createWorkshopMembershipModule } from '.'
import { useCloudbaseAdmin } from '../../utils/cloudbase-admin'
import {
  PERSONAL_WORKSHOPS_COLLECTION,
  WORKSHOP_EVENTS_COLLECTION,
  WORKSHOP_MEMBERSHIPS_COLLECTION,
  workshopMembershipId,
} from '../catalog/cloudbase'

export function createCloudbaseWorkshopMembershipModule(
  db: CloudbaseAdminDb = useCloudbaseAdmin().db,
) {
  return createWorkshopMembershipModule(createCloudbaseWorkshopMembershipDataSource(db))
}

export function createCloudbaseWorkshopMembershipDataSource(
  db: CloudbaseAdminDb,
): WorkshopMembershipDataSource {
  return {
    async getWorkshop(workshopId) {
      const { data } = await db.collection(PERSONAL_WORKSHOPS_COLLECTION).doc(workshopId).get()
      return first<PersonalWorkshop>(data)
    },
    async getMembership(workshopId, userUid) {
      const { data } = await db.collection(WORKSHOP_MEMBERSHIPS_COLLECTION)
        .doc(workshopMembershipId(workshopId, userUid))
        .get()
      return first<WorkshopMembership>(data)
    },
    async commitMembershipChange(membership, event) {
      const eventId = `workshop_event_${randomUUID().replace(/-/g, '')}`
      await db.runTransaction(async (transaction: CloudbaseTransaction) => {
        await transaction.collection(WORKSHOP_MEMBERSHIPS_COLLECTION)
          .doc(workshopMembershipId(membership.workshopId, membership.userUid))
          .set(membership)
        await transaction.collection(WORKSHOP_EVENTS_COLLECTION).doc(eventId).set(event)
      })
    },
  }
}

function first<T>(value: unknown): T | null {
  if (Array.isArray(value))
    return (value[0] as T | undefined) || null
  return value ? value as T : null
}
