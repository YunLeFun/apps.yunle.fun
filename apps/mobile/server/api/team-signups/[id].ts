import { Buffer } from 'node:buffer'
import { createError, getRouterParam, readRawBody, setResponseHeader } from 'h3'
import { requireRegisteredCloudbaseUser } from '../../utils/cloudbase-auth'
import { createTeamSignup, getTeamSignup, setTeamSignupParticipation, validateSignupId } from '../../utils/team-signups'

export default defineEventHandler(async (event) => {
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
  const { method } = event
  if (method !== 'GET' && method !== 'PUT' && method !== 'PATCH') {
    setResponseHeader(event, 'Allow', 'GET, PUT, PATCH')
    throw createError({ statusCode: 405, message: '请求方法不可用' })
  }
  const { uid } = await requireRegisteredCloudbaseUser(event)
  const id = validateSignupId(getRouterParam(event, 'id'))
  if (method === 'GET')
    return getTeamSignup(id, uid)

  const body = await readRawBody(event)
  if (!body || Buffer.byteLength(body) > 1024)
    throw createError({ statusCode: 400, message: '报名请求格式错误' })
  let input: unknown
  try {
    input = JSON.parse(body)
  }
  catch {
    throw createError({ statusCode: 400, message: '报名请求格式错误' })
  }
  return method === 'PUT' ? createTeamSignup(id, uid, input) : setTeamSignupParticipation(id, uid, input)
})
