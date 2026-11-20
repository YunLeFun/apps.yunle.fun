import type { CloudbaseAdminDb, CloudbaseTransaction } from './cloudbase-admin'
import { createHash } from 'node:crypto'
import { createError } from 'h3'
import { useCloudbaseAdmin } from './cloudbase-admin'

const collection = 'conversation_boards'
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
const themeColor = /^#[0-9a-f]{6}$/i
const identityHash = /^[0-9a-f]{64}$/

type Seat = 'black' | 'white'
interface Position { row: number, column: number }
interface Move extends Position { actionId: string }
interface Scene {
  schemaVersion: 1
  size: number
  palette: { board: string, grid: string, black: string, white: string }
  interaction: { gesture: 'drag-to-place', action: 'place' }
}
interface Board { scene: Scene, black: string, white: string | null, moves: Move[] }

const defaultScene: Scene = {
  schemaVersion: 1,
  size: 9,
  palette: { board: '#e4b578', grid: '#583820', black: '#242027', white: '#fff7e9' },
  interaction: { gesture: 'drag-to-place', action: 'place' },
}

function fields(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {}
}

function validId(id: unknown): id is string {
  return typeof id === 'string' && id.length === 36 && uuid.test(id)
}

export function boardId(id: string | undefined): string {
  if (!validId(id))
    fail(400, 'BOARD_INVALID', '棋盘编号无效')
  return id
}

function fail(statusCode: number, code: string, message: string): never {
  throw createError({ statusCode, message, data: { code } })
}

function color(value: unknown): value is string {
  return typeof value === 'string' && value.length === 7 && themeColor.test(value)
}

function parseScene(value: unknown): Scene | undefined {
  const { schemaVersion, size, palette, interaction } = fields(value)
  const { board, grid, black, white } = fields(palette)
  const { gesture, action } = fields(interaction)
  if (schemaVersion !== 1 || typeof size !== 'number' || !Number.isInteger(size) || size < 5 || size > 15
    || !color(board) || !color(grid) || !color(black) || !color(white) || gesture !== 'drag-to-place' || action !== 'place') {
    return
  }
  return { schemaVersion, size, palette: { board, grid, black, white }, interaction: { gesture, action } }
}

function position(value: unknown, size: number): Position | undefined {
  const { row, column } = fields(value)
  if (typeof row === 'number' && Number.isInteger(row) && row >= 0 && row < size
    && typeof column === 'number' && Number.isInteger(column) && column >= 0 && column < size) {
    return { row, column }
  }
}

function cell(point: Position, size: number) {
  return point.row * size + point.column
}

function readBoard(response: { data?: unknown, code?: unknown }): Board | undefined {
  if (response.code)
    fail(503, 'BOARD_UNAVAILABLE', '暂时无法读取棋局')
  const stored = Array.isArray(response.data) ? response.data[0] : response.data
  if (stored == null)
    return
  const { scene, black, white, moves } = fields(stored)
  const parsed = parseScene(scene)
  if (!parsed || typeof black !== 'string' || !identityHash.test(black)
    || (white !== null && (typeof white !== 'string' || !identityHash.test(white) || white === black))
    || !Array.isArray(moves) || moves.length > parsed.size ** 2 || (!white && moves.length)) {
    fail(503, 'BOARD_UNAVAILABLE', '棋局数据暂不可用')
  }

  const occupied = new Set<number>()
  const actions = new Set<string>()
  const validated = moves.map((move) => {
    const point = position(move, parsed.size)
    const { actionId } = fields(move)
    if (!point || !validId(actionId) || actions.has(actionId) || occupied.has(cell(point, parsed.size)))
      fail(503, 'BOARD_UNAVAILABLE', '棋局数据暂不可用')
    actions.add(actionId)
    occupied.add(cell(point, parsed.size))
    return { ...point, actionId }
  })
  return { scene: parsed, black, white, moves: validated }
}

function readRequired(response: Parameters<typeof readBoard>[0]) {
  return readBoard(response) ?? fail(404, 'BOARD_MISSING', '找不到这局五子棋')
}

function seatOf(index: number): Seat {
  return index % 2 === 0 ? 'black' : 'white'
}

function viewerKey(id: string, uid: string) {
  return createHash('sha256').update(JSON.stringify([id, uid])).digest('hex')
}

function winnerOf(moves: Move[], size: number): Seat | null {
  const last = moves.at(-1)
  if (!last || moves.length < 9)
    return null
  const winner = seatOf(moves.length - 1)
  const stones = new Set(moves.flatMap((move, index) => seatOf(index) === winner ? [cell(move, size)] : []))
  for (const [dy, dx] of [[0, 1], [1, 0], [1, 1], [1, -1]] as const) {
    let count = 1
    for (const direction of [-1, 1]) {
      let row = last.row + dy * direction
      let column = last.column + dx * direction
      while (row >= 0 && row < size && column >= 0 && column < size && stones.has(cell({ row, column }, size))) {
        count++
        row += dy * direction
        column += dx * direction
      }
    }
    if (count >= 5)
      return winner
  }
  return null
}

function snapshot(id: string, board: Board, viewer: string) {
  const seat = board.black === viewer ? 'black' : board.white === viewer ? 'white' : null
  const winner = winnerOf(board.moves, board.scene.size)
  const status = !board.white ? 'waiting' : winner ? 'won' : board.moves.length === board.scene.size ** 2 ? 'draw' : 'playing'
  return {
    schemaVersion: 1 as const,
    boardId: id,
    scene: board.scene,
    revision: 1 + Number(board.white !== null) + board.moves.length,
    status,
    seat,
    turn: status === 'playing' ? seatOf(board.moves.length) : null,
    winner,
    pieces: board.moves.map(({ row, column }, index) => ({ row, column, color: seatOf(index) })),
  }
}

export type BoardSnapshot = ReturnType<typeof snapshot>

export async function getBoard(id: string, uid: string, db = useCloudbaseAdmin().db) {
  return snapshot(id, readRequired(await db.collection(collection).doc(id).get()), viewerKey(id, uid))
}

function verifyWrite(id: string, result: { code?: unknown, updated?: number, upserted?: unknown[] }) {
  if (result.code || (result.updated !== 1 && !result.upserted?.some(value => fields(value)._id === id)))
    fail(503, 'BOARD_UNAVAILABLE', '暂时无法保存棋局')
}

export async function createBoard(id: string, uid: string, input: unknown, db: CloudbaseAdminDb = useCloudbaseAdmin().db): Promise<BoardSnapshot> {
  const { scene } = fields(input)
  const template = scene === undefined ? defaultScene : parseScene(scene)
  if (!template || !input || typeof input !== 'object' || Array.isArray(input))
    fail(400, 'BOARD_INVALID', '棋盘模板格式无效')
  const viewer = viewerKey(id, uid)
  return db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const doc = transaction.collection(collection).doc(id)
    const current = readBoard(await doc.get())
    if (current) {
      if (current.black !== viewer || (scene !== undefined && JSON.stringify(current.scene) !== JSON.stringify(template)))
        fail(409, 'BOARD_CONFLICT', '棋盘已存在')
      return snapshot(id, current, viewer)
    }
    const created: Board = { scene: template, black: viewer, white: null, moves: [] }
    verifyWrite(id, await doc.set(created))
    return snapshot(id, created, viewer)
  })
}

export async function actOnBoard(id: string, uid: string, input: unknown, db: CloudbaseAdminDb = useCloudbaseAdmin().db, joinRevision?: number): Promise<BoardSnapshot> {
  const command = fields(input)
  const viewer = viewerKey(id, uid)
  if (command.action !== 'join' && command.action !== 'place')
    fail(400, 'BOARD_INVALID', '棋局指令无效')
  return db.runTransaction(async (transaction: CloudbaseTransaction) => {
    const doc = transaction.collection(collection).doc(id)
    const current = readRequired(await doc.get())
    const before = snapshot(id, current, viewer)
    let next: Board
    if (command.action === 'join') {
      if (before.seat)
        return before
      if (current.white)
        fail(409, 'BOARD_FULL', '两席已满，可以观战')
      if (joinRevision !== undefined && joinRevision !== before.revision)
        fail(409, 'BOARD_CONFLICT', '棋局已变化，请再试')
      next = { ...current, white: viewer }
    }
    else {
      const point = position(command, current.scene.size)
      const { actionId, expectedRevision } = command
      if (!point || !validId(actionId) || !Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 2)
        fail(400, 'BOARD_INVALID', '落子指令无效')
      if (!before.seat)
        fail(403, 'BOARD_SPECTATOR', '观战者不能落子')
      const index = current.moves.findIndex(move => move.actionId === actionId)
      if (index >= 0) {
        const previous = current.moves[index]!
        if (seatOf(index) === before.seat && previous.row === point.row && previous.column === point.column
          && expectedRevision === index + 2) {
          return before
        }
        fail(409, 'BOARD_CONFLICT', '落子指令已使用')
      }
      if (expectedRevision !== before.revision || before.status !== 'playing' || before.turn !== before.seat
        || current.moves.some(move => move.row === point.row && move.column === point.column)) {
        fail(409, 'BOARD_CONFLICT', '棋局已变化，请重新落子')
      }
      next = { ...current, moves: [...current.moves, { ...point, actionId }] }
    }
    verifyWrite(id, await doc.set(next))
    return snapshot(id, next, viewer)
  })
}
