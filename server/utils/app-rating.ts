import type { CloudbaseAdminDb } from './cloudbase-admin'
import { summarizeRatingGroups } from './reviews'

/**
 * 重算某应用的真实评分聚合，并去规范化回写到 apps 文档（rating + ratingCount）。
 *
 * 评分真实来源是 app_reviews 的已发布评论聚合：详情页用实时聚合（见 reviews GET），
 * 列表则读 apps 文档上的这份缓存。在评论发布/更新/删除后调用以保持缓存新鲜。
 *
 * 失败不抛——评分回写是副作用，不应阻断评论提交/删除主流程（调用方用 .catch 吞掉）。
 * appId 命中 apps._id 时优先按 _id 回写；缺省/未命中则回退 slug == appKey。
 */
export async function recomputeAppRating(
  db: CloudbaseAdminDb,
  appKey: string,
  appId?: string,
): Promise<void> {
  if (!appKey)
    return

  const reviews = db.collection('app_reviews')
  const apps = db.collection('apps')

  const summaryResult = await reviews
    .aggregate()
    .match({ appKey, status: 'published' })
    .group({ _id: '$rating', count: db.command.aggregate.sum(1) })
    .end()
  const summary = summarizeRatingGroups(summaryResult?.data || [])

  const patch = {
    rating: summary.average,
    ratingCount: summary.count,
    ratingUpdatedAt: Date.now(),
  }

  // 优先按文档 _id 回写；未命中再按 slug（appKey 通常即 slug）
  if (appId) {
    const res = await apps.doc(appId).update(patch) as { updated?: number }
    if (res?.updated)
      return
  }
  await apps.where({ slug: appKey }).update(patch)
}
