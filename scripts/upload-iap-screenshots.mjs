#!/usr/bin/env node
/**
 * 为 IAP 商品上传 App 审核截图（让商品从 MISSING_METADATA → READY_TO_SUBMIT，
 * 沙盒/生产 StoreKit 才会返回该商品）。
 * 运行：node scripts/upload-iap-screenshots.mjs
 */

import { createHash, createSign } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { deflateSync } from 'node:zlib'

const KEY_ID = '3BCG9ZYMR8'
const ISSUER_ID = '73b700d9-9661-417c-bfa4-0ceedd7a38e2'
const KEY_PATH = '/Users/yunyou/Downloads/AuthKey_3BCG9ZYMR8.p8'
const APP_ID = '6759859441'
const BASE_URL = 'https://api.appstoreconnect.apple.com'

let _jwt = null
let _exp = 0
function getJwt() {
  const now = Math.floor(Date.now() / 1000)
  if (_jwt && now < _exp - 60) return _jwt
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
  const res = await fetch(`${BASE_URL}${path}`, {
    ...opts,
    headers: { Authorization: `Bearer ${getJwt()}`, 'Content-Type': 'application/json', ...opts.headers },
  })
  const text = await res.text()
  let body = {}
  try { body = text ? JSON.parse(text) : {} } catch { /* non-json */ }
  if (!res.ok) {
    const m = body.errors?.map(e => `${e.code}: ${e.detail}`).join('; ') ?? `${res.status} ${text.slice(0, 200)}`
    throw new Error(m)
  }
  return body
}

/** 生成一张纯色 PNG（1242×2208，App Store 经典 5.5" 截图尺寸） */
function makePng(w, h, [r, g, b]) {
  const crcTable = (() => {
    const t = []
    for (let n = 0; n < 256; n++) {
      let c = n
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1
      t[n] = c >>> 0
    }
    return t
  })()
  const crc32 = (buf) => {
    let c = 0xFFFFFFFF
    for (let i = 0; i < buf.length; i++) c = crcTable[(c ^ buf[i]) & 0xFF] ^ (c >>> 8)
    return (c ^ 0xFFFFFFFF) >>> 0
  }
  const chunk = (type, data) => {
    const len = Buffer.alloc(4)
    len.writeUInt32BE(data.length)
    const typeBuf = Buffer.from(type, 'ascii')
    const crc = Buffer.alloc(4)
    crc.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])))
    return Buffer.concat([len, typeBuf, data, crc])
  }
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(w, 0)
  ihdr.writeUInt32BE(h, 4)
  ihdr[8] = 8        // bit depth
  ihdr[9] = 2        // color type RGB
  // rest 0
  const row = Buffer.alloc(1 + w * 3)
  for (let x = 0; x < w; x++) {
    row[1 + x * 3] = r
    row[1 + x * 3 + 1] = g
    row[1 + x * 3 + 2] = b
  }
  const raw = Buffer.concat(Array.from({ length: h }, () => row))
  const idat = deflateSync(raw, { level: 9 })
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr),
    chunk('IDAT', idat),
    chunk('IEND', Buffer.alloc(0)),
  ])
}

async function listProducts() {
  const d = await api(`/v1/apps/${APP_ID}/inAppPurchasesV2?limit=200&fields[inAppPurchases]=productId,state`)
  return d.data
}

async function hasScreenshot(iapId) {
  const d = await api(`/v2/inAppPurchases/${iapId}?include=appStoreReviewScreenshot`)
  return !!d.data?.relationships?.appStoreReviewScreenshot?.data
}

async function uploadScreenshot(iapId, productId, png) {
  // 1) 预留上传位
  const reserve = await api('/v1/inAppPurchaseAppStoreReviewScreenshots', {
    method: 'POST',
    body: JSON.stringify({
      data: {
        type: 'inAppPurchaseAppStoreReviewScreenshots',
        attributes: { fileName: `${productId}.png`, fileSize: png.length },
        relationships: { inAppPurchaseV2: { data: { type: 'inAppPurchases', id: iapId } } },
      },
    }),
  })
  const scId = reserve.data.id
  const ops = reserve.data.attributes.uploadOperations || []

  // 2) 按 uploadOperations 切片上传
  for (const op of ops) {
    const headers = {}
    for (const hh of op.requestHeaders || []) headers[hh.name] = hh.value
    const slice = png.subarray(op.offset, op.offset + op.length)
    const up = await fetch(op.url, { method: op.method, headers, body: slice })
    if (!up.ok) throw new Error(`upload chunk failed: ${up.status} ${await up.text()}`)
  }

  // 3) 提交（commit），带源文件 MD5
  const md5 = createHash('md5').update(png).digest('hex')
  await api(`/v1/inAppPurchaseAppStoreReviewScreenshots/${scId}`, {
    method: 'PATCH',
    body: JSON.stringify({
      data: {
        type: 'inAppPurchaseAppStoreReviewScreenshots',
        id: scId,
        attributes: { uploaded: true, sourceFileChecksum: md5 },
      },
    }),
  })
}

async function main() {
  const png = makePng(1242, 2208, [124, 92, 255]) // 品牌紫
  console.log(`生成占位截图 1242×2208，${(png.length / 1024).toFixed(0)} KB\n`)

  const products = await listProducts()
  for (const prod of products) {
    const id = prod.id
    const pid = prod.attributes.productId
    process.stdout.write(`[${pid}]  state=${prod.attributes.state}  `)
    try {
      if (await hasScreenshot(id)) {
        console.log('已有截图，跳过')
        continue
      }
      await uploadScreenshot(id, pid, png)
      console.log('✓ 截图已上传')
    } catch (e) {
      console.log(`✗ ${e.message}`)
    }
  }
  console.log('\n等待几秒让 Apple 处理，再查状态：node scripts/check-iap-state.mjs')
}

main().catch(e => { console.error(e); process.exit(1) })
