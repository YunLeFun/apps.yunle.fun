import type { ServerAuthUser } from './cloudbase-auth'
import type { AppRecord } from '~/types/app'
import { createError } from 'h3'
import { normalizeMarketShortName } from '../domain/app-identifiers'
import { APPS_COLLECTION, createAppSubmission, submitOwnedAppToPublicMarket, updateAppSubmission } from './app-submissions'
import { readOwnedApplicationState, requireAppIdentityMigration } from './app-write-version'
import { useCloudbaseAdmin } from './cloudbase-admin'
import { webBuildVersionUrl } from './web-build-config'
import { getWebBuildForSubmission } from './web-build-storage'

export async function submitWebBuildToMarket(user: ServerAuthUser, id: string, revision: unknown, shortName: unknown) {
  const { db } = useCloudbaseAdmin()
  const { page, releaseId } = await getWebBuildForSubmission(id, user.uid, revision)
  await requireAppIdentityMigration(db)
  const slug = `web-build-${id}`
  const matches = await db.collection(APPS_COLLECTION).where({ slug, ownerUid: user.uid }).limit(1).get()
  const existing = matches.data?.[0] as AppRecord | undefined
  const state = existing ? await readOwnedApplicationState(db, existing._id, user.uid) : null
  const reservedName = state?.listing?.shortName ?? normalizeMarketShortName(shortName)
  const websiteUrl = webBuildVersionUrl(id, releaseId)
  const input = {
    name: page.title,
    description: page.description,
    slug,
    websiteUrl,
    privacyPolicyUrl: 'https://www.yunle.fun/docs/privacy-policy',
    supportUrl: 'https://apps.yunle.fun/feedback',
    emoji: '🌐',
    category: '其他',
    audience: 'public',
  }

  let app
  if (!state) {
    app = (await createAppSubmission(user, input, id)).app
  }
  else if (state.app.websiteUrl !== websiteUrl || state.app.publicationStatus !== 'published') {
    app = (await updateAppSubmission(user, state.app._id, input, `"${state.writeVersion}"`, id)).app
  }
  else {
    app = { ...state.app, writeVersion: state.writeVersion }
  }

  await submitOwnedAppToPublicMarket(user, app._id, {
    ifMatch: `"${app.writeVersion}"`,
    shortName: reservedName,
    webBuild: {
      id,
      async verify(transaction) {
        const current = await getWebBuildForSubmission(id, user.uid, revision, transaction)
        if (current.releaseId !== releaseId)
          throw createError({ statusCode: 409, statusMessage: '已发布版本发生变化，请刷新后再投稿' })
      },
    },
  })
  return { slug }
}
