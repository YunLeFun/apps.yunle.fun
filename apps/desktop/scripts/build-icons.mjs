import { Buffer } from 'node:buffer'
import { execFile } from 'node:child_process'
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import process from 'node:process'
import { promisify } from 'node:util'

const exec = promisify(execFile)
const desktop = path.resolve(import.meta.dirname, '..')
const icons = path.join(desktop, 'build/icons')
const source = path.join(icons, 'source.png')
const publicDirectory = path.join(desktop, 'public')
const pngSignature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])

function pngSize(data) {
  if (!data.subarray(0, 8).equals(pngSignature) || data.toString('ascii', 12, 16) !== 'IHDR')
    throw new Error('Expected a PNG image with an IHDR chunk')
  return { width: data.readUInt32BE(16), height: data.readUInt32BE(20) }
}

async function checkPng(file, size) {
  const data = await fs.readFile(file)
  const dimensions = pngSize(data)
  if (dimensions.width !== size || dimensions.height !== size)
    throw new Error(`Incorrect dimensions: ${file}`)
  return data
}

async function resize(size, output) {
  await exec('/usr/bin/sips', ['--setProperty', 'format', 'png', '--resampleHeightWidth', String(size), String(size), source, '--out', output])
  await checkPng(output, size)
}

// ICO stores a directory followed by one PNG payload per size. A 256-pixel
// dimension is encoded as zero in its directory entry, per the ICO format.
function icoFromPngs(images) {
  const header = Buffer.alloc(6 + images.length * 16)
  header.writeUInt16LE(1, 2)
  header.writeUInt16LE(images.length, 4)
  let offset = header.length
  for (const [index, { size, data }] of images.entries()) {
    const entry = 6 + index * 16
    header.writeUInt8(size === 256 ? 0 : size, entry)
    header.writeUInt8(size === 256 ? 0 : size, entry + 1)
    header.writeUInt16LE(1, entry + 4)
    header.writeUInt16LE(32, entry + 6)
    header.writeUInt32LE(data.length, entry + 8)
    header.writeUInt32LE(offset, entry + 12)
    offset += data.length
  }
  return Buffer.concat([header, ...images.map(image => image.data)])
}

function checkIco(data, sizes) {
  if (data.readUInt16LE(0) !== 0 || data.readUInt16LE(2) !== 1 || data.readUInt16LE(4) !== sizes.length)
    throw new Error('Invalid ICO directory')
  let expectedOffset = 6 + sizes.length * 16
  for (const [index, size] of sizes.entries()) {
    const entry = 6 + index * 16
    const offset = data.readUInt32LE(entry + 12)
    const length = data.readUInt32LE(entry + 8)
    const width = data.readUInt8(entry) || 256
    const height = data.readUInt8(entry + 1) || 256
    const payload = pngSize(data.subarray(offset, offset + length))
    if (offset !== expectedOffset || width !== size || height !== size || payload.width !== size || payload.height !== size)
      throw new Error('Invalid ICO image entry')
    expectedOffset += length
  }
  if (expectedOffset !== data.length)
    throw new Error('Invalid ICO payload length')
}

if (process.platform !== 'darwin')
  throw new Error('Regenerate icons on macOS with sips and iconutil; other platforms use the committed assets.')

await checkPng(source, 1024)
await fs.mkdir(publicDirectory, { recursive: true })
const sizes = [16, 32, 48, 64, 128, 256, 512, 1024]
for (const size of sizes) {
  const output = path.join(icons, `icon-${size}.png`)
  if (size === 1024)
    await fs.copyFile(source, output)
  else
    await resize(size, output)
}
await fs.copyFile(path.join(icons, 'icon-512.png'), path.join(icons, 'icon.png'))

const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'yunlefun-icons-'))
try {
  const iconset = path.join(directory, 'icon.iconset')
  await fs.mkdir(iconset)
  for (const size of [16, 32, 128, 256, 512]) {
    await fs.copyFile(path.join(icons, `icon-${size}.png`), path.join(iconset, `icon_${size}x${size}.png`))
    await fs.copyFile(path.join(icons, `icon-${size * 2}.png`), path.join(iconset, `icon_${size}x${size}@2x.png`))
  }
  const output = path.join(icons, 'icon.icns')
  await exec('/usr/bin/iconutil', ['--convert', 'icns', iconset, '--output', output])
  const icns = await fs.readFile(output)
  if (icns.toString('ascii', 0, 4) !== 'icns' || icns.readUInt32BE(4) !== icns.length)
    throw new Error('Invalid ICNS container')
}
finally {
  await fs.rm(directory, { recursive: true, force: true })
}

const icoSizes = [16, 32, 48, 256]
const icoImages = []
for (const size of icoSizes)
  icoImages.push({ size, data: await checkPng(path.join(icons, `icon-${size}.png`), size) })
const ico = icoFromPngs(icoImages)
checkIco(ico, icoSizes)
await fs.writeFile(path.join(icons, 'icon.ico'), ico)
await fs.writeFile(path.join(publicDirectory, 'favicon.ico'), ico)

for (const [name, size] of [
  ['apple-touch-icon.png', 180],
  ['pwa-192x192.png', 192],
  ['pwa-512x512.png', 512],
  ['maskable-icon.png', 512],
]) {
  await resize(size, path.join(publicDirectory, name))
}

console.info('Generated YunLeFun ICNS, 16/32/48/256 ICO, Linux PNG and browser icons from the unchanged 1024 PNG.')
