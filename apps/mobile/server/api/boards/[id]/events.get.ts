import { getRouterParam, setResponseHeader } from 'h3'
import { useCloudbaseAdmin } from '../../../utils/cloudbase-admin'
import { requireRegisteredCloudbaseUser } from '../../../utils/cloudbase-auth'
import { boardId, getBoard } from '../../../utils/conversation-boards'
import { streamConversationSnapshots } from '../../../utils/conversation-snapshots'

export default defineEventHandler(async (event) => {
  setResponseHeader(event, 'Cache-Control', 'private, no-store, no-transform')
  const { uid } = await requireRegisteredCloudbaseUser(event)
  const id = boardId(getRouterParam(event, 'id'))
  const { db } = useCloudbaseAdmin()
  return streamConversationSnapshots(event, () => getBoard(id, uid, db), snapshot => snapshot.status === 'won' || snapshot.status === 'draw', snapshot => snapshot.status === 'waiting' ? 2_000 : 1_000, 'BOARD_UNAVAILABLE')
})
