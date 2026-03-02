/**
 * 云乐坊链接
 */
export const YLF_LINKS = {
  /**
   * 工作室
   */
  studio: {
    label: '云乐坊工作室',
    text: 'studio.yunle.fun',
    url: 'https://studio.yunle.fun',
  },
}

/**
 * 联系方式
 */
export const YLF_CONTACT = {
  /** 业务合作 */
  business: {
    label: '业务合作',
    email: 'i@yunle.fun',
  },
  /** 问题反馈 / 客服 */
  support: {
    label: '问题反馈',
    email: 'kf@yunle.fun',
  },
  /** 微信客服 */
  wxKf: {
    label: '联系客服',
    url: 'https://work.weixin.qq.com/kfid/kfc9d4dcc4b6bd1c69e',
  },
}

/**
 * 官方网站
 */
export const YLF_WEBSITES = [
  {
    label: '官网',
    url: 'https://www.yunle.fun',
    /** Iconify icon name (used by @nuxt/icon <Icon>) */
    icon: 'ri:global-line',
    /** 品牌色 */
    color: '#007aff',
    /** 域名，展示在右侧 */
    domain: 'www.yunle.fun',
  },
  {
    label: '工作室',
    url: 'https://studio.yunle.fun',
    icon: 'ri:cloud-line',
    color: '#5856d6',
    domain: 'studio.yunle.fun',
  },
]

/**
 * 社交媒体
 */
export const YLF_SOCIAL_MEDIA = [
  {
    label: 'GitHub',
    url: 'https://github.com/yunlefun',
    icon: 'simple-icons:github',
    color: '#333333',
    /** 账号名称，展示在右侧 */
    handle: 'YunLeFun',
  },
  {
    label: '微信公众号',
    url: '', // 无外链，展示二维码或提示搜索
    icon: 'simple-icons:wechat',
    color: '#07c160',
    /** 公众号名称，用于提示用户搜索 */
    wxOfficialName: '云乐坊工作室',
    handle: '云乐坊工作室',
  },
  {
    label: 'X (Twitter)',
    url: 'https://x.com/yunlefun',
    icon: 'simple-icons:x',
    color: '#333333',
    handle: '@yunlefun',
  },
  {
    label: 'Bilibili',
    url: 'https://space.bilibili.com/yunlefun',
    icon: 'simple-icons:bilibili',
    color: '#00a1d6',
    handle: '云乐坊工作室',
  },
]
