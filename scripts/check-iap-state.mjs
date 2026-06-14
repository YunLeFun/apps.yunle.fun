#!/usr/bin/env node
/** 查询 IAP 商品当前状态。运行：node scripts/check-iap-state.mjs */
import { createSign } from 'node:crypto'
import { readFileSync } from 'node:fs'

const KEY_ID = '3BCG9ZYMR8'
const ISSUER_ID = '73b700d9-9661-417c-bfa4-0ceedd7a38e2'
const KEY_PATH = '/Users/yunyou/Downloads/AuthKey_3BCG9ZYMR8.p8'
const APP_ID = '6759859441'

const now = Math.floor(Date.now() / 1000)
const pk = readFileSync(KEY_PATH, 'utf8')
const h = Buffer.from(JSON.stringify({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' })).toString('base64url')
const p = Buffer.from(JSON.stringify({ iss: ISSUER_ID, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' })).toString('base64url')
const s = createSign('SHA256')
s.update(`${h}.${p}`)
s.end()
const jwt = `${h}.${p}.${s.sign({ key: pk, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`

const r = await fetch(`https://api.appstoreconnect.apple.com/v1/apps/${APP_ID}/inAppPurchasesV2?limit=200&fields[inAppPurchases]=productId,name,state,inAppPurchaseType`, {
  headers: { Authorization: `Bearer ${jwt}` },
})
const d = await r.json()
for (const x of d.data || [])
  console.log(x.attributes.productId.padEnd(32), x.attributes.state)
if (d.errors) console.log(JSON.stringify(d.errors, null, 2))
