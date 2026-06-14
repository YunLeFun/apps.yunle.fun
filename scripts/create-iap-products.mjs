#!/usr/bin/env node
/**
 * 通过 App Store Connect REST API 批量创建 IAP 商品
 * 运行：node scripts/create-iap-products.mjs
 */

import { createSign } from 'crypto'
import { readFileSync } from 'fs'

const KEY_ID = '3BCG9ZYMR8'
const ISSUER_ID = '73b700d9-9661-417c-bfa4-0ceedd7a38e2'
const KEY_PATH = '/Users/yunyou/Downloads/AuthKey_3BCG9ZYMR8.p8'
const BUNDLE_ID = 'fun.yunle.apps'
const BASE_URL = 'https://api.appstoreconnect.apple.com'

const PRODUCTS = [
  {
    productId: 'fun.yunle.apps.coin_100',
    name: '100 云币',
    type: 'CONSUMABLE',
    priceY: '12',
    zh: { displayName: '100 云币', description: '100 云币' },
    en: { displayName: '100 Coins', description: '100 Yunle coins' },
  },
  {
    productId: 'fun.yunle.apps.coin_500',
    name: '500 云币',
    type: 'CONSUMABLE',
    priceY: '58',
    zh: { displayName: '500 云币', description: '500 云币' },
    en: { displayName: '500 Coins', description: '500 Yunle coins' },
  },
  {
    productId: 'fun.yunle.apps.coin_1000',
    name: '1000 云币',
    type: 'CONSUMABLE',
    priceY: '108',
    zh: { displayName: '1000 云币', description: '1000 云币' },
    en: { displayName: '1000 Coins', description: '1000 Yunle coins' },
  },
  {
    productId: 'fun.yunle.apps.member_month',
    name: '会员月度',
    type: 'NON_RENEWING_SUBSCRIPTION',
    priceY: '12',
    zh: { displayName: '云乐坊会员（月度）', description: '云乐坊会员 · 1 个月（31 天）' },
    en: { displayName: 'Yunle Member (Monthly)', description: 'Yunle membership · 1 month (31 days)' },
  },
  {
    productId: 'fun.yunle.apps.member_year',
    name: '会员年度',
    type: 'NON_RENEWING_SUBSCRIPTION',
    priceY: '118',
    zh: { displayName: '云乐坊会员（年度）', description: '云乐坊会员 · 1 年（366 天）' },
    en: { displayName: 'Yunle Member (Yearly)', description: 'Yunle membership · 1 year (366 days)' },
  },
]

let _jwt = null
let _jwtExp = 0

function getJwt() {
  const now = Math.floor(Date.now() / 1000)
  if (_jwt && now < _jwtExp - 60) return _jwt

  const privateKey = readFileSync(KEY_PATH, 'utf8')
  const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' })).toString('base64url')
  const payload = Buffer.from(JSON.stringify({
    iss: ISSUER_ID, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1',
  })).toString('base64url')

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
    headers: { Authorization: `Bearer ${getJwt()}`, 'Content-Type': 'application/json', ...opts.headers },
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

async function getAppId() {
  const { data } = await api(`/v1/apps?filter[bundleId]=${BUNDLE_ID}&fields[apps]=bundleId,name`)
  if (!data[0]) throw new Error(`App "${BUNDLE_ID}" not found — is it created in ASC?`)
  console.log(`  App: ${data[0].attributes.name}  id=${data[0].id}`)
  return data[0].id
}

async function createProduct(appId, p) {
  try {
    const { data } = await api('/v2/inAppPurchases', {
      method: 'POST',
      body: JSON.stringify({
        data: {
          type: 'inAppPurchases',
          attributes: { name: p.name, productId: p.productId, inAppPurchaseType: p.type, reviewNote: '' },
          relationships: { app: { data: { type: 'apps', id: appId } } },
        },
      }),
    })
    console.log(`    ✓ Created  id=${data.id}`)
    return data.id
  } catch (e) {
    // If already exists, try to find it
    if (e.message.includes('already exists') || e.message.includes('DUPLICATE')) {
      console.log(`    ℹ Already exists, fetching existing...`)
      const { data } = await api(`/v1/apps/${appId}/inAppPurchasesV2?filter[productId]=${p.productId}&fields[inAppPurchases]=productId`)
      if (data[0]) { console.log(`    ✓ Found existing  id=${data[0].id}`); return data[0].id }
    }
    throw e
  }
}

async function addLocalizations(iapId, p) {
  for (const [locale, loc] of [['zh-Hans', p.zh], ['en-US', p.en]]) {
    await api('/v1/inAppPurchaseLocalizations', {
      method: 'POST',
      body: JSON.stringify({
        data: {
          type: 'inAppPurchaseLocalizations',
          attributes: { name: loc.displayName, description: loc.description, locale },
          relationships: { inAppPurchaseV2: { data: { type: 'inAppPurchases', id: iapId } } },
        },
      }),
    })
    console.log(`    ✓ Localization: ${locale}`)
  }
}

async function fetchAllPricePoints(iapId) {
  const all = []
  let url = `/v2/inAppPurchases/${iapId}/pricePoints?filter[territory]=CHN&limit=200&fields[inAppPurchasePricePoints]=customerPrice,proceeds`
  while (url) {
    const res = await api(url)
    all.push(...res.data)
    url = res.links?.next ? res.links.next.replace(BASE_URL, '') : null
  }
  return all
}

async function setPricing(iapId, p) {
  let pps
  try {
    pps = await fetchAllPricePoints(iapId)
  } catch (e) {
    console.log(`    ⚠ Could not fetch price points: ${e.message}`)
    console.log(`      → Set price ¥${p.priceY} manually in ASC`)
    return
  }

  const target = parseFloat(p.priceY)
  const match = pps.find(pp => Math.abs(parseFloat(pp.attributes?.customerPrice ?? 'NaN') - target) < 0.01)

  if (!match) {
    console.log(`    ⚠ ¥${p.priceY} not found in ${pps.length} price points`)
    console.log(`      → Set price manually in ASC`)
    return
  }

  // ASC inline creation requires ${local-id} format
  const tmpId = '${tmpPrice}'
  await api('/v1/inAppPurchasePriceSchedules', {
    method: 'POST',
    body: JSON.stringify({
      data: {
        type: 'inAppPurchasePriceSchedules',
        relationships: {
          inAppPurchase: { data: { type: 'inAppPurchases', id: iapId } },
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
  console.log(`    ✓ Price: ¥${p.priceY} CNY`)
}

async function main() {
  console.log('App Store Connect — 创建 IAP 商品\n')

  const appId = await getAppId()

  for (const p of PRODUCTS) {
    console.log(`\n[${p.productId}]  ${p.type}`)
    try {
      const iapId = await createProduct(appId, p)
      await addLocalizations(iapId, p)
      await setPricing(iapId, p)
    } catch (e) {
      console.error(`    ✗ ${e.message}`)
    }
  }

  console.log('\n完成。请在 ASC 确认商品状态，并提交审核。')
}

main()
