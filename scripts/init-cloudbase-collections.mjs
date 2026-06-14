#!/usr/bin/env node
/**
 * 初始化评价/举报/审核系统所需的 CloudBase 集合（幂等：已存在则跳过）。
 *
 * 运行：node --env-file=.env scripts/init-cloudbase-collections.mjs
 * 依赖 .env 中的 NUXT_TENCENT_API_SECRET_ID / NUXT_TENCENT_API_SECRET_KEY
 * （envId 缺省用 yunlefun-8g7ybcxc7345c490，可用 NUXT_TCB_ENV_ID 覆盖）。
 */
import { createRequire } from 'node:module'
import process from 'node:process'

const require = createRequire(import.meta.url)
const cloudbase = require('@cloudbase/node-sdk')

const env = process.env.NUXT_TCB_ENV_ID || process.env.TCB_ENV_ID || 'yunlefun-8g7ybcxc7345c490'
const secretId = process.env.NUXT_TENCENT_API_SECRET_ID
const secretKey = process.env.NUXT_TENCENT_API_SECRET_KEY

if (!secretId || !secretKey) {
  console.error('✗ 缺少 NUXT_TENCENT_API_SECRET_ID / NUXT_TENCENT_API_SECRET_KEY，请用 `node --env-file=.env` 运行')
  process.exit(1)
}

const app = cloudbase.init({ env, secretId, secretKey })
const db = app.database()

const collections = ['app_reviews', 'app_reports', 'moderation_tasks']

for (const name of collections) {
  try {
    await db.createCollection(name)
    console.log(`✓ 已创建集合 ${name}`)
  }
  catch (e) {
    const msg = e?.message || String(e)
    if (/exist|已存在|ResourceInUse|ResourceUnavailable/i.test(msg))
      console.log(`↩ 集合 ${name} 已存在，跳过`)
    else
      console.error(`✗ ${name}: ${msg}`)
  }
}
console.log(`完成（env=${env}）`)
