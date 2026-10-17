import http from 'node:http'
import process from 'node:process'
import cloudbase from '@cloudbase/node-sdk'
import { createDiscoveryHandler } from './handler.js'

const envId = process.env.CLOUDBASE_ENV_ID || process.env.TCB_ENV_ID || process.env.NUXT_PUBLIC_TCB_ENV_ID || 'yunlefun-8g7ybcxc7345c490'
const region = process.env.CLOUDBASE_REGION || process.env.TCB_REGION || 'ap-shanghai'
const app = cloudbase.init({ env: envId })
const handler = createDiscoveryHandler({ db: app.database(), envId, region, dailyLimit: Number(process.env.AGENT_DAILY_LIMIT || 50) })
const server = http.createServer((req, res) => {
  handler(req, res).catch(() => {
    if (!res.headersSent)
      res.writeHead(503, { 'content-type': 'application/json', 'cache-control': 'private, no-store' })
    res.end()
  })
})
server.listen(Number(process.env.PORT || 9000))
