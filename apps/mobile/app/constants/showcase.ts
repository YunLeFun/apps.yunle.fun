/**
 * apps.yunle.fun 根路径展示页的内容。
 *
 * 截图来自原生 iOS 客户端（apps/ios）的实际运行画面，存放在 public/showcase。
 * 重新截取时保持 1206×2622 原始比例，状态栏统一为 9:41。
 */

export interface ShowcaseFeature {
  id: string
  kicker: string
  title: string
  body: string
  points: string[]
  shot: string
  alt: string
  /** 设备背后的氛围光颜色 */
  glow: string
}

export const SHOWCASE_FEATURES: ShowcaseFeature[] = [
  {
    id: 'home',
    kicker: '云居',
    title: '你的应用，\n住在这里。',
    body: '像 iPhone 主屏幕一样收纳喜欢的云应用。最近使用与常用应用一目了然，登录后在设备之间同步。',
    points: ['最近使用', '常用应用', '云端同步'],
    shot: '/showcase/home.jpg',
    alt: '云居主屏幕：最近使用、常用应用与我的应用',
    glow: '#0a84ff',
  },
  {
    id: 'discovery',
    kicker: '寻乐',
    title: '每天，\n一点新乐趣。',
    body: '官方出品与创作者作品按内容编排。不用翻找，打开就有惊喜。',
    points: ['官方精选', '随手发现'],
    shot: '/showcase/discovery.jpg',
    alt: '寻乐页：精选应用卡片与官方出品列表',
    glow: '#30d158',
  },
  {
    id: 'workshop',
    kicker: '工坊',
    title: '想要的应用，\n搜索即得。',
    body: '按分类筛选，按用途或作者搜索。轻点即可试用，喜欢就带回云居。',
    points: ['分类筛选', '即点即用', '无需安装'],
    shot: '/showcase/workshop.jpg',
    alt: '工坊页：搜索栏与全部应用列表',
    glow: '#bf5af2',
  },
  {
    id: 'detail',
    kicker: '获取',
    title: '轻点获取，\n即刻拥有。',
    body: '使用条件、评分与评价、真实预览都清清楚楚。获取后自动加入云居，打开就能用。',
    points: ['使用条件透明', '评分与评价', '一键分享'],
    shot: '/showcase/detail.jpg',
    alt: '应用详情页：获取按钮与已加入云居提示',
    glow: '#ff9f0a',
  },
  {
    id: 'assistant',
    kicker: 'AI 助手',
    title: '说出想做的事，\n它帮你找到应用。',
    body: '用自然语言描述需求，助手从目录里挑出最合适的云应用，直接打开或加入云居。',
    points: ['自然语言', '应用卡片', '随时停止'],
    shot: '/showcase/assistant.jpg',
    alt: 'AI 助手对话页',
    glow: '#64d2ff',
  },
  {
    id: 'me',
    kicker: '我的',
    title: '一个账号，\n通行所有云应用。',
    body: '云乐坊账号统一登录。云币、会员与购买记录集中管理，多个账号随心切换。',
    points: ['统一登录', '钱包与会员', '多账号'],
    shot: '/showcase/me.jpg',
    alt: '我的页面：账号、钱包、会员与设置入口',
    glow: '#ff375f',
  },
]

export interface ShowcaseCraft {
  icon: string
  title: string
  body: string
}

export const SHOWCASE_CRAFT: ShowcaseCraft[] = [
  { icon: 'ri:drop-line', title: 'Liquid Glass', body: '导航栏、标签栏与工具栏直接采用系统材质，随系统一起进化。' },
  { icon: 'ri:fingerprint-line', title: '恰到好处的触感', body: '获取、移除、筛选，每个动作都有与之匹配的触感反馈。' },
  { icon: 'ri:accessibility-line', title: '为每个人设计', body: '动态字体、VoiceOver 与“减弱动态效果”全面适配。' },
  { icon: 'ri:contrast-2-line', title: '深色模式', body: '跟随系统切换，应用图标也有专属的深色版本。' },
  { icon: 'ri:shield-keyhole-line', title: '隐私优先', body: '凭据保存在钥匙串，云应用只拿到一次性授权码。' },
  { icon: 'ri:flashlight-line', title: '即点即用', body: '云应用无需下载安装，打开即用，随时恢复上次的会话。' },
]

/**
 * 下载渠道。上架后填入正式链接，留空时按钮显示“即将上架”。
 */
export const SHOWCASE_DOWNLOADS = {
  appStore: '',
  android: '',
}

/** 网页版入口。 */
export const WEB_APP_ENTRY = '/tabs/home'
/** 用户主动进入网页版后记住选择，下次访问根路径直接进入。 */
export const WEB_ENTRY_STORAGE_KEY = 'ylf:web-entry'
