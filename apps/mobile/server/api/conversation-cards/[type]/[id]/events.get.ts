import { getRouterParam, setResponseHeader } from 'h3'
import { useCloudbaseAdmin } from '../../../../utils/cloudbase-admin'
import { requireRegisteredCloudbaseUser } from '../../../../utils/cloudbase-auth'
import { cardReference, getConversationCard } from '../../../../utils/conversation-cards'
import { streamConversationSnapshots } from '../../../../utils/conversation-snapshots'

export default defineEventHandler(async (event) => {
  setResponseHeader(event, 'Cache-Control', 'private, no-store, no-transform')
  const { uid } = await requireRegisteredCloudbaseUser(event)
  const reference = cardReference(getRouterParam(event, 'type'), getRouterParam(event, 'id'))
  const { db } = useCloudbaseAdmin()
  return streamConversationSnapshots(event, () => getConversationCard(reference, uid, db), snapshot => snapshot.finished, () => reference.type === 'play.board' ? 1_000 : 2_000)
})
