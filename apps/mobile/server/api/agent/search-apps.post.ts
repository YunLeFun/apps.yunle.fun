import type { SearchAppsInput } from '../../utils/agent-search-apps'
import { createError, readBody } from 'h3'
import { searchApps } from '../../utils/agent-search-apps'
import { requireCloudbaseUser } from '../../utils/cloudbase-auth'

const MAX_QUERY_LENGTH = 120
const MAX_CATEGORY_LENGTH = 40

export default defineEventHandler(async (event) => {
  await requireCloudbaseUser(event)

  const input = normalizeSearchAppsInput(await readBody(event))
  const apps = await searchApps(input)

  return {
    code: 0,
    data: {
      apps,
    },
  }
})

function normalizeSearchAppsInput(value: unknown): SearchAppsInput {
  if (!isRecord(value)) {
    throw createError({
      statusCode: 400,
      message: '请求参数无效',
    })
  }

  const query = stringValue(value.query)
  if (!query) {
    throw createError({
      statusCode: 400,
      message: '请输入搜索关键词',
    })
  }

  return {
    query: query.slice(0, MAX_QUERY_LENGTH),
    category: stringValue(value.category)?.slice(0, MAX_CATEGORY_LENGTH),
    limit: numberValue(value.limit),
  }
}

function stringValue(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined
}

function numberValue(value: unknown): number | undefined {
  if (typeof value !== 'number' || !Number.isFinite(value))
    return undefined
  return value
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
