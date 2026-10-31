import { readFile, mkdir, writeFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

// Input is the Play build export, never a separately maintained native list.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const sourceIndex = process.argv.indexOf('--source')
if (sourceIndex < 0 || !process.argv[sourceIndex + 1])
  throw new Error('Pass --source <Play build native/catalog-v1.json>')
const source = resolve(process.argv[sourceIndex + 1])
const data = await readFile(source)
const catalog = JSON.parse(data.toString('utf8'))
if (data.length > 1_048_576 || catalog.schemaVersion !== 1 || !catalog.catalogVersion || !Array.isArray(catalog.games))
  throw new Error('Unsupported Play native catalog export')
const destination = resolve(root, 'apps/ios/YunleFun/Resources/native-game-catalog-v1.json')
await mkdir(dirname(destination), { recursive: true })
await writeFile(destination, `${JSON.stringify(catalog, null, 2)}\n`)
process.stdout.write(`Synced ${catalog.games.length} games from Play catalog ${catalog.catalogVersion}\n`)
