/**
 * 版本更新日志
 */
export interface ChangelogEntry {
  version: string
  date: string
  changes: string[]
}

export const APP_CHANGELOG: ChangelogEntry[] = [
  {
    version: '0.0.1',
    date: '2026-03-03',
    changes: [
      '首个版本发布',
      '应用聚合浏览和搜索',
      '支持微信登录、手机号登录',
      '个人资料管理',
      '深色模式支持',
    ],
  },
]
