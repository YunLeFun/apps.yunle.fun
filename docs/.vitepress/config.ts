import { defineConfig } from 'vitepress'

export default defineConfig({
  title: '云乐坊',
  description: '云乐坊 (yunle.fun) — 云应用聚合平台产品设计文档',

  lang: 'zh-CN',

  themeConfig: {
    logo: '/logo.svg',

    nav: [
      { text: '指南', link: '/guide/getting-started', activeMatch: '/guide/' },
      { text: '产品设计', link: '/design/', activeMatch: '/design/' },
      { text: 'UI 设计', link: '/ui/', activeMatch: '/ui/' },
      { text: '数据库', link: '/database/', activeMatch: '/database/' },
      { text: '开发笔记', link: '/dev/', activeMatch: '/dev/' },
      { text: '路线图', link: '/roadmap', activeMatch: '/roadmap' },
    ],

    sidebar: [
      {
        text: '指南',
        items: [
          { text: '快速开始', link: '/guide/getting-started' },
          { text: 'JSAPI 接入（window.ylf）', link: '/guide/jsapi' },
        ],
      },
      {
        text: '产品设计',
        collapsed: false,
        items: [
          { text: '什么是云乐坊', link: '/product/' },
          { text: '核心概念', link: '/product/concepts' },
          { text: 'Tab 页架构', link: '/product/tabs-architecture' },
          { text: '云居 - Home Screen', link: '/product/home' },
          { text: '寻乐 - Discovery', link: '/product/discovery' },
          { text: '工坊 - Workshop', link: '/product/workshop' },
          { text: '互动指标（收藏/访问/有用/投币）', link: '/product/app-engagement-metrics' },
        ],
      },
      {
        text: 'UI 设计',
        collapsed: false,
        items: [
          { text: 'Ionic + Konsta UI 实践', link: '/ui/' },
        ],
      },
      {
        text: '数据库',
        collapsed: false,
        items: [
          { text: '概览', link: '/database/' },
          { text: 'apps 集合', link: '/database/apps' },
          { text: 'featured_apps 集合', link: '/database/featured-apps' },
          { text: 'user_desktops 集合', link: '/database/user-desktops' },
          { text: 'weekly_charts 集合', link: '/database/weekly-charts' },
        ],
      },
      {
        text: '开发笔记',
        collapsed: false,
        items: [
          { text: '概览', link: '/dev/' },
          { text: '认证', link: '/dev/auth' },
          { text: '扫码功能', link: '/dev/barcode-scanner' },
          { text: '沉浸式内嵌浏览器', link: '/dev/in-app-browser' },
          { text: '短信登录', link: '/dev/sms-login' },
          { text: 'Home Screen 拖拽排序', link: '/dev/home-screen-drag' },
          { text: 'App Store 上架手册', link: '/dev/app-store-onboarding' },
          { text: 'TestFlight 内测上架', link: '/dev/testflight' },
          { text: 'CloudBase 安全规则', link: '/dev/cloudbase-rules' },
          { text: '错误监控（Tencent RUM）', link: '/dev/rum' },
          { text: '隐私政策核对清单', link: '/dev/privacy-checklist' },
          { text: '依赖安全（pnpm audit）', link: '/dev/dependency-security' },
        ],
      },
      {
        text: '发布',
        collapsed: false,
        items: [
          { text: '路线图', link: '/roadmap' },
        ],
      },
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/YunYouJun/apps.yunle.fun' },
    ],

    footer: {
      message: 'Made with ❤️ by YunYouJun',
      copyright: 'Copyright © 2024-present',
    },

    search: {
      provider: 'local',
    },

    outline: {
      level: [2, 3],
      label: '目录',
    },

    lastUpdated: {
      text: '最后更新',
    },

    docFooter: {
      prev: '上一页',
      next: '下一页',
    },
  },
})
