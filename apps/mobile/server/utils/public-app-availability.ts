import type { CloudbaseAdminDb } from './cloudbase-admin'
import { useCloudbaseAdmin } from './cloudbase-admin'

export type PublicAppUnavailableReason = 'not_listed' | 'delisted' | 'suspended' | 'unavailable'

/** Only public listing state is exposed; review notes and private app metadata stay private. */
export async function publicAppUnavailableReason(
  key: string,
  db: CloudbaseAdminDb = useCloudbaseAdmin().db,
): Promise<PublicAppUnavailableReason> {
  const { data } = await db.collection('public_market_listings')
    .where(db.command.or([{ appId: key }, { shortName: key.toLowerCase() }]))
    .field({ appId: true, shortName: true, status: true, approvedRevisionId: true })
    .limit(2)
    .get()
  const rows: unknown = data
  if (!Array.isArray(rows) || rows.length !== 1)
    return 'unavailable'
  const listing: unknown = rows[0]
  if (!listing || typeof listing !== 'object'
    || !('approvedRevisionId' in listing) || typeof listing.approvedRevisionId !== 'string' || !listing.approvedRevisionId
    || !('status' in listing)) {
    return 'unavailable'
  }
  switch (listing.status) {
    case 'unlisted': return 'not_listed'
    case 'delisted': return 'delisted'
    case 'suspended': return 'suspended'
    default: return 'unavailable'
  }
}
