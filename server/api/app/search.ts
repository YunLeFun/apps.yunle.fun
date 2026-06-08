import type { YlfAppInfo } from '@yunlefun/types'

export default defineEventHandler((event) => {
  const query = getQuery(event)
  if (!query.id) {
    return {
      code: 400,
      message: '缺少参数 id',
    }
  }

  let appInfo: YlfAppInfo
  if (query.id === '2') {
    appInfo = {
      id: '2',
      themeColor: 'orange',
      logo: 'https://cook.yunyoujun.cn/favicon.svg',
      name: '食用手册',
      slug: 'cook',
      emoji: '🍳',
      websiteUrl: 'https://cook.yunyoujun.cn',
    }

    return {
      code: 0,
      data: appInfo,
    }
  }
  else {
    return {
      code: 404,
      message: '应用未找到',
    }
  }
})
