import type { CloudbaseAdminDb } from './cloudbase-admin'
import type { BoardSnapshot } from './conversation-boards'
import { createError } from 'h3'
import { useCloudbaseAdmin } from './cloudbase-admin'
import { actOnBoard, getBoard } from './conversation-boards'
import { getTeamSignup, setTeamSignupParticipation, validateSignupId } from './team-signups'

type CardType = 'team.signup' | 'play.board'
interface CardReference { type: CardType, instanceId: string }
interface CardAction { label: string, enabled: boolean }
type Component
  = { kind: 'title' | 'text', field: string }
    | { kind: 'seats', filled: string, total: string }
    | { kind: 'button', action: string }
    | { kind: 'gomoku', field: string, action: string }
export interface CardSnapshot {
  schemaVersion: 1
  reference: CardReference
  revision: number
  finished: boolean
  fallbackText: string
  template: { schemaVersion: 1, components: Component[] }
  data: Record<string, string | number | BoardSnapshot>
  actions: Record<string, CardAction>
}

const templates: Record<CardType, CardSnapshot['template']> = {
  'team.signup': {
    schemaVersion: 1,
    components: [
      { kind: 'title', field: 'title' },
      { kind: 'seats', filled: 'memberCount', total: 'capacity' },
      { kind: 'text', field: 'count' },
      { kind: 'text', field: 'status' },
      { kind: 'button', action: 'signup.join' },
      { kind: 'button', action: 'signup.cancel' },
    ],
  },
  'play.board': {
    schemaVersion: 1,
    components: [
      { kind: 'title', field: 'title' },
      { kind: 'text', field: 'status' },
      { kind: 'gomoku', field: 'board', action: 'board.place' },
      { kind: 'text', field: 'hint' },
      { kind: 'button', action: 'board.join' },
    ],
  },
}

export function cardReference(type: string | undefined, id: string | undefined): CardReference {
  if (type !== 'team.signup' && type !== 'play.board')
    throw createError({ statusCode: 404, message: '找不到这张卡片' })
  return { type, instanceId: validateSignupId(id) }
}

function cardDocument(reference: CardReference, revision: number, fallbackText: string, data: CardSnapshot['data'], actions: CardSnapshot['actions'], finished = false): CardSnapshot {
  return { schemaVersion: 1, reference, revision, fallbackText, finished, template: templates[reference.type], data, actions }
}

function signupCard(reference: CardReference, signup: Awaited<ReturnType<typeof getTeamSignup>>) {
  const hasSpace = signup.memberCount < signup.capacity
  return cardDocument(reference, signup.revision, signup.title, {
    title: signup.title,
    memberCount: signup.memberCount,
    capacity: signup.capacity,
    count: `${signup.memberCount}/${signup.capacity} 人已报名`,
    status: signup.joined ? '已报名' : hasSpace ? '' : '席位已满',
  }, signup.joined
    ? { 'signup.cancel': { label: '取消报名', enabled: true } }
    : { 'signup.join': { label: '报名', enabled: hasSpace } })
}

function boardStatus(board: BoardSnapshot): string {
  switch (board.status) {
    case 'waiting': return board.seat === 'black' ? '你执黑 · 等待对手' : '等待白棋加入'
    case 'draw': return '和棋'
    case 'won': return board.winner === 'black' ? '黑棋获胜' : '白棋获胜'
    default: {
      const role = board.seat === 'black' ? '你执黑' : board.seat === 'white' ? '你执白' : '观战'
      return `${role} · ${board.seat === board.turn ? '轮到你' : board.turn === 'black' ? '黑棋落子' : '白棋落子'}`
    }
  }
}

function boardCard(reference: CardReference, board: BoardSnapshot) {
  const actions: CardSnapshot['actions'] = {}
  if (board.status === 'waiting' && board.seat === null)
    actions['board.join'] = { label: '加入执白', enabled: true }
  if (board.status === 'playing' && board.seat === board.turn)
    actions['board.place'] = { label: '落子', enabled: true }
  return cardDocument(reference, board.revision, '联机五子棋', {
    title: '联机五子棋',
    status: boardStatus(board),
    hint: board.status === 'playing' && board.seat ? '点按空交点落子，也可以拖动下方棋子。' : '',
    board,
  }, actions, board.status === 'won' || board.status === 'draw')
}

export async function getConversationCard(reference: CardReference, uid: string, db = useCloudbaseAdmin().db): Promise<CardSnapshot> {
  return reference.type === 'team.signup'
    ? signupCard(reference, await getTeamSignup(reference.instanceId, uid, db))
    : boardCard(reference, await getBoard(reference.instanceId, uid, db))
}

function fields(input: unknown): Record<string, unknown> {
  return input && typeof input === 'object' && !Array.isArray(input) ? input as Record<string, unknown> : {}
}

export async function actOnConversationCard(reference: CardReference, uid: string, value: unknown, db: CloudbaseAdminDb = useCloudbaseAdmin().db): Promise<CardSnapshot> {
  const { schemaVersion, action, expectedRevision, actionId, input } = fields(value)
  if (schemaVersion !== 1 || typeof expectedRevision !== 'number' || !Number.isSafeInteger(expectedRevision)
    || expectedRevision < 1 || typeof actionId !== 'string') {
    throw createError({ statusCode: 400, message: '卡片动作格式错误' })
  }
  validateSignupId(actionId)
  const { instanceId } = reference
  if (reference.type === 'team.signup' && (action === 'signup.join' || action === 'signup.cancel') && input === undefined) {
    return signupCard(reference, await setTeamSignupParticipation(instanceId, uid, {
      joined: action === 'signup.join',
    }, db, expectedRevision))
  }
  if (reference.type === 'play.board') {
    if (action === 'board.join' && input === undefined)
      return boardCard(reference, await actOnBoard(instanceId, uid, { action: 'join' }, db, expectedRevision))
    if (action === 'board.place') {
      const { row, column } = fields(input)
      return boardCard(reference, await actOnBoard(instanceId, uid, { action: 'place', row, column, expectedRevision, actionId }, db))
    }
  }
  throw createError({ statusCode: 400, message: '这张卡片不支持该动作' })
}
