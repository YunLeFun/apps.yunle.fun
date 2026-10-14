import { createError } from 'h3'
import { WorkshopMembershipError } from '../domain/workshop-membership'

export function rethrowWorkshopMembershipError(error: unknown): never {
  if (!(error instanceof WorkshopMembershipError))
    throw error
  const statusCode = error.code === 'WORKSHOP_NOT_FOUND'
    ? 404
    : error.code === 'WORKSHOP_JOIN_RATE_LIMITED'
      ? 429
      : error.code === 'WORKSHOP_OWNER_REQUIRED' || error.code === 'WORKSHOP_MEMBER_BLOCKED'
        ? 403
        : 409
  throw createError({
    statusCode,
    message: error.message,
    data: { code: error.code },
  })
}
