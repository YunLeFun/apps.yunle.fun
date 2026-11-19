import { Buffer } from 'node:buffer'
import { createHash, timingSafeEqual } from 'node:crypto'

const host = 'build.yunle.app'
const maxHTMLBytes = 24_576
const pagePath = /^\/site\/([a-f0-9]{32})(?:\/([a-f0-9]{32})\.html)?$/
const uploadPath = /^\/_publish\/([a-f0-9]{32})\/([a-f0-9]{32})\.html$/
const idPattern = /^[a-f0-9]{32}$/
const digestPattern = /^[a-f0-9]{64}$/

const baseHeaders = {
  'Cache-Control': 'no-store',
  'Referrer-Policy': 'no-referrer',
  'X-Content-Type-Options': 'nosniff',
  'X-Robots-Tag': 'noindex, nofollow',
}

function empty(status) {
  return new Response(null, { status, headers: baseHeaders })
}

function key(id, release) {
  return `${id}/${release}.html`
}

function matchesDigest(object, sha256) {
  const checksum = object?.checksums?.sha256
  return Boolean(checksum && Buffer.from(checksum).toString('hex') === sha256)
}

function mayUpload(request, expected) {
  const supplied = request.headers.get('Authorization')?.match(/^Bearer ([a-f0-9]{64})$/)?.[1]
  return Boolean(supplied && typeof expected === 'string' && digestPattern.test(expected)
    && expected.length === 64 && timingSafeEqual(Buffer.from(supplied), Buffer.from(expected)))
}

async function readBytes(body, limit) {
  if (!body)
    return null

  const reader = body.getReader()
  const chunks = []
  let length = 0
  try {
    for (;;) {
      const { done, value } = await reader.read()
      if (done)
        return Buffer.concat(chunks, length)
      length += value.byteLength
      if (length > limit) {
        await reader.cancel()
        return null
      }
      chunks.push(value)
    }
  }
  finally {
    reader.releaseLock()
  }
}

async function upload(request, env, id, release) {
  if (request.method !== 'PUT' || !mayUpload(request, env.WEB_BUILD_WRITE_TOKEN))
    return empty(404)
  if (request.headers.get('Content-Type') !== 'text/html; charset=utf-8')
    return empty(415)
  const html = await readBytes(request.body, maxHTMLBytes)
  if (!html?.length)
    return empty(413)

  const digest = createHash('sha256').update(html).digest('hex')
  const filename = key(id, release)
  const result = await env.PAGES.put(filename, html, {
    onlyIf: new Headers({ 'If-None-Match': '*' }),
    sha256: digest,
    httpMetadata: { contentType: 'text/html; charset=utf-8' },
  })
  if (result)
    return empty(201)
  const stored = await env.PAGES.head(filename)
  return empty(matchesDigest(stored, digest) ? 204 : 409)
}

async function serve(request, env, id, version) {
  const path = `/api/web-builds/public/${id}${version ? `/${version}` : ''}`
  const response = await fetch(new URL(path, env.APPS_ORIGIN), {
    redirect: 'manual',
    cache: 'no-store',
    signal: AbortSignal.timeout(5_000),
  })
  if (response.status === 404)
    return empty(404)
  if (!response.ok)
    return empty(503)
  const bytes = await readBytes(response.body, 1024)
  if (!bytes?.length)
    return empty(503)
  const { releaseId, sha256 } = JSON.parse(bytes.toString('utf8')) ?? {}
  if (typeof releaseId !== 'string' || releaseId.length !== 32 || !idPattern.test(releaseId)
    || (version && releaseId !== version) || typeof sha256 !== 'string' || sha256.length !== 64 || !digestPattern.test(sha256)) {
    return empty(503)
  }

  const filename = key(id, releaseId)
  const object = request.method === 'HEAD' ? await env.PAGES.head(filename) : await env.PAGES.get(filename)
  if (!object || !matchesDigest(object, sha256)) {
    if (object && 'body' in object)
      await object.body.cancel()
    return empty(503)
  }
  return new Response('body' in object ? object.body : null, {
    headers: {
      ...baseHeaders,
      'Content-Type': 'text/html; charset=utf-8',
      'Content-Security-Policy': 'default-src \'none\'; style-src \'unsafe-inline\'; base-uri \'none\'; form-action \'none\'; frame-ancestors \'none\'; sandbox allow-top-navigation-to-custom-protocols',
      'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), payment=()',
      'X-Yunle-Web-Build-Release': releaseId,
      'X-Yunle-Web-Build-Sha256': sha256,
    },
  })
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url)
    if (url.protocol !== 'https:' || url.host !== host)
      return empty(404)
    try {
      const write = uploadPath.exec(url.pathname)
      if (write)
        return await upload(request, env, write[1], write[2])
      const page = pagePath.exec(url.pathname)
      if (page && (request.method === 'GET' || request.method === 'HEAD'))
        return await serve(request, env, page[1], page[2])
      return empty(404)
    }
    catch (error) {
      console.error('Web Build request failed', error instanceof Error ? error.name : 'UnknownError')
      return empty(503)
    }
  },
}
