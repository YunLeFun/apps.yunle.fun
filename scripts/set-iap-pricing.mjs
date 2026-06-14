#!/usr/bin/env node
/**
 * 为已创建的 IAP 商品补设价格
 * 运行：node scripts/set-iap-pricing.mjs
 */

import { createSign } from 'node:crypto'
import { readFileSync } from 'node:fs'

const KEY_ID = '3BCG9ZYMR8'
const ISSUER_ID = '73b700d9-9661-417c-bfa4-0ceedd7a38e2'
const KEY_PATH = '/Users/yunyou/Downloads/AuthKey_3BCG9ZYMR8.p8'
const BASE_URL = 'https://api.appstoreconnect.apple.com'

// IDs from the creation run
const PRODUCTS = [
  { iapId: '6779227213', productId: 'coin_100', priceY: '12' },
  { iapId: '6779227233', productId: 'coin_500', priceY: '58' },
  { iapId: '6779227444', productId: 'coin_1000', priceY: '108' },
  { iapId: '6779227282', productId: 'member_month', priceY: '12' },
  { iapId: '6779227518', productId: 'member_year', priceY: '118' },
]

let _jwt = null
let _jwtExp = 0

function getJwt() {
  const now = Math.floor(Date.now() / 1000)
  if (_jwt && now < _jwtExp - 60)
    return _jwt
  const privateKey = readFileSync(KEY_PATH, 'utf8')
  const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' })).toString('base64url')
  const payload = Buffer.from(JSON.stringify({ iss: ISSUER_ID, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' })).toString('base64url')
  const sign = createSign('SHA256')
  sign.update(`${header}.${payload}`)
  sign.end()
  const sig = sign.sign({ key: privateKey, dsaEncoding: 'ieee-p1363' })
  _jwt = `${header}.${payload}.${sig.toString('base64url')}`
  _jwtExp = now + 1200
  return _jwt
}

async function api(path, opts = {}) {
  const res = await fetch(`${BASE_URL}${path}`, {
    ...opts,
    headers: { 'Authorization': `Bearer ${getJwt()}`, 'Content-Type': 'application/json', ...opts.headers },
  })
  const text = await res.text()
  let body
  try { body = JSON.parse(text) }
  catch { throw new Error(`Non-JSON (${res.status}): ${text.slice(0, 300)}`) }
  if (!res.ok) {
    const msgs = body.errors?.map(e => `${e.code}: ${e.detail}`).join('; ') ?? JSON.stringify(body)
    throw new Error(`HTTP ${res.status} — ${msgs}`)
  }
  return body
}

async function fetchAllPricePoints(iapId) {
  const all = []
  let path = `/v2/inAppPurchases/${iapId}/pricePoints?filter[territory]=CHN&limit=200&fields[inAppPurchasePricePoints]=customerPrice,proceeds`
  while (path) {
    const res = await api(path)
    all.push(...res.data)
    path = res.links?.next ? res.links.next.replace(BASE_URL, '') : null
    if (path)
      console.log(`      paginating… (${all.length} so far)`)
  }
  return all
}

async function setPrice(p) {
  console.log(`\n[${p.productId}]  target ¥${p.priceY}`)

  const pps = await fetchAllPricePoints(p.iapId)
  console.log(`    fetched ${pps.length} price points`)

  const target = Number.parseFloat(p.priceY)
  const match = pps.find(pp => Math.abs(Number.parseFloat(pp.attributes?.customerPrice ?? 'NaN') - target) < 0.01)

  if (!match) {
    // Show the closest values
    const sorted = [...pps].sort((a, b) =>
      Math.abs(Number.parseFloat(a.attributes?.customerPrice) - target)
      - Math.abs(Number.parseFloat(b.attributes?.customerPrice) - target),
    )
    const near = sorted.slice(0, 5).map(pp => pp.attributes?.customerPrice).join(', ')
    console.log(`    ⚠ ¥${p.priceY} not found. Nearest: ${near}`)
    console.log(`      → Set price manually in ASC`)
    return
  }

  console.log(`    found price point id=${match.id}  customerPrice=${match.attributes.customerPrice}`)

  // '${tmpPrice}' is the literal format required by ASC for inline creation
  const tmpId = '${tmpPrice}'
  await api('/v1/inAppPurchasePriceSchedules', {
    method: 'POST',
    body: JSON.stringify({
      data: {
        type: 'inAppPurchasePriceSchedules',
        relationships: {
          inAppPurchase: { data: { type: 'inAppPurchases', id: p.iapId } },
          manualPrices: { data: [{ type: 'inAppPurchasePrices', id: tmpId }] },
          baseTerritory: { data: { type: 'territories', id: 'CHN' } },
        },
      },
      included: [{
        id: tmpId,
        type: 'inAppPurchasePrices',
        attributes: { startDate: null },
        relationships: {
          inAppPurchasePricePoint: { data: { type: 'inAppPurchasePricePoints', id: match.id } },
          territory: { data: { type: 'territories', id: 'CHN' } },
        },
      }],
    }),
  })
  console.log(`    ✓ Price set: ¥${p.priceY} CNY`)
}

async function main() {
  console.log('设置 IAP 商品价格\n')
  for (const p of PRODUCTS) {
    try { await setPrice(p) }
    catch (e) { console.error(`    ✗ ${e.message}`) }
  }
  console.log('\n完成。')
}

main()
