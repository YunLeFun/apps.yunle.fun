#!/usr/bin/env node
/**
 * 为 IAP 商品设置上架区域（全区域可售 + 新区域自动可售）。
 * 缺这一步商品会一直卡在 MISSING_METADATA，沙盒/生产 StoreKit 拉不到。
 * 运行：node scripts/set-iap-availability.mjs
 */
import { createSign } from 'node:crypto'
import { readFileSync } from 'node:fs'

const KEY_ID = '3BCG9ZYMR8'
const ISSUER_ID = '73b700d9-9661-417c-bfa4-0ceedd7a38e2'
const KEY_PATH = '/Users/yunyou/Downloads/AuthKey_3BCG9ZYMR8.p8'
const APP_ID = '6759859441'
const BASE = 'https://api.appstoreconnect.apple.com'

let _jwt = null
let _exp = 0
function getJwt() {
  const now = Math.floor(Date.now() / 1000)
  if (_jwt && now < _exp - 60)
    return _jwt
  const pk = readFileSync(KEY_PATH, 'utf8')
  const h = Buffer.from(JSON.stringify({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' })).toString('base64url')
  const p = Buffer.from(JSON.stringify({ iss: ISSUER_ID, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' })).toString('base64url')
  const s = createSign('SHA256')
  s.update(`${h}.${p}`)
  s.end()
  _jwt = `${h}.${p}.${s.sign({ key: pk, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`
  _exp = now + 1200
  return _jwt
}

async function api(path, opts = {}) {
  for (let i = 0; i < 4; i++) {
    try {
      const res = await fetch(`${BASE}${path}`, {
        ...opts,
        headers: { 'Authorization': `Bearer ${getJwt()}`, 'Content-Type': 'application/json', ...opts.headers },
      })
      const text = await res.text()
      let body = {}
      try { body = text ? JSON.parse(text) : {} }
      catch { /* */ }
      if (!res.ok) {
        const m = body.errors?.map(e => `${e.code}: ${e.detail}`).join('; ') ?? `${res.status} ${text.slice(0, 200)}`
        throw new Error(m)
      }
      return body
    }
    catch (e) {
      if (i === 3)
        throw e
      await new Promise(r => setTimeout(r, 800))
    }
  }
}

async function allTerritories() {
  const ids = []
  let path = '/v1/territories?limit=200'
  while (path) {
    const d = await api(path)
    ids.push(...d.data.map(t => t.id))
    path = d.links?.next ? d.links.next.replace(BASE, '') : null
  }
  return ids
}

async function listProducts() {
  const d = await api(`/v1/apps/${APP_ID}/inAppPurchasesV2?limit=200&fields[inAppPurchases]=productId,state`)
  return d.data
}

async function hasAvailability(id) {
  const r = await api(`/v2/inAppPurchases/${id}?include=inAppPurchaseAvailability`)
  return !!r.data?.relationships?.inAppPurchaseAvailability?.data
}

async function main() {
  const territories = await allTerritories()
  console.log(`全区域共 ${territories.length} 个\n`)
  const terrData = territories.map(id => ({ type: 'territories', id }))

  const products = await listProducts()
  for (const prod of products) {
    const id = prod.id
    const pid = prod.attributes.productId
    process.stdout.write(`[${pid}]  `)
    try {
      if (await hasAvailability(id)) {
        console.log('已设区域，跳过')
        continue
      }
      await api('/v1/inAppPurchaseAvailabilities', {
        method: 'POST',
        body: JSON.stringify({
          data: {
            type: 'inAppPurchaseAvailabilities',
            attributes: { availableInNewTerritories: true },
            relationships: {
              inAppPurchase: { data: { type: 'inAppPurchases', id } },
              availableTerritories: { data: terrData },
            },
          },
        }),
      })
      console.log('✓ 全区域可售')
    }
    catch (e) {
      console.log(`✗ ${e.message}`)
    }
  }
  console.log('\n等待处理后查状态：node scripts/check-iap-state.mjs')
}

main().catch((e) => { console.error(e); process.exit(1) })
