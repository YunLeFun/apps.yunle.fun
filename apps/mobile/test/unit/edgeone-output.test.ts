import { mkdir, mkdtemp, rm, symlink, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { assertNoDeploymentEnvFiles, verifyEdgeOneOutput } from '../../scripts/check-edgeone-output.mjs'

const temporaryRoots: string[] = []

async function fixture({ adapted = false } = {}) {
  const root = await mkdtemp(join(tmpdir(), 'yunlefun-edgeone-output-test-'))
  temporaryRoots.push(root)
  const output = join(root, '.edgeone')
  const server = join(output, 'cloud-functions/ssr-node')
  const files = {
    'nitro.json': JSON.stringify({ preset: 'node-server', framework: { name: 'nuxt' } }),
    'assets/index.html': '<html>Cloud apps</html>',
    'assets/_nuxt/app.js': 'export {}',
    [`cloud-functions/ssr-node/${adapted ? 'handler.js' : 'index.mjs'}`]: 'export {}',
    'cloud-functions/ssr-node/chunks/nitro/nitro.mjs': 'export {}',
    'cloud-functions/ssr-node/package.json': JSON.stringify({ dependencies: { '@cloudbase/node-sdk': '3.18.3' } }),
    'cloud-functions/ssr-node/node_modules/@cloudbase/node-sdk/package.json': '{}',
    ...(adapted
      ? {
          'cloud-functions/ssr-node/config.json': JSON.stringify({
            version: 3,
            routes: [{ handle: 'filesystem' }, { src: '^/api/(.*)$' }, { src: '^/(.*)$' }],
          }),
        }
      : {}),
  }
  for (const [name, contents] of Object.entries(files)) {
    const file = join(output, name)
    await mkdir(dirname(file), { recursive: true })
    await writeFile(file, contents)
  }
  return { root, output, server }
}

afterEach(async () => {
  await Promise.all(temporaryRoots.splice(0).map(root => rm(root, { recursive: true, force: true })))
})

describe('edgeOne full-stack deployment output', () => {
  it('accepts Nitro output before the platform creates its handler and routes', async () => {
    const { output } = await fixture()
    await expect(verifyEdgeOneOutput(output)).resolves.toBeUndefined()
    await expect(verifyEdgeOneOutput(output, { adapted: true })).rejects.toThrow('full-stack output is incomplete')
  })

  it('accepts the final official handler and page/API route fallback after index cleanup', async () => {
    const { output } = await fixture({ adapted: true })
    await expect(verifyEdgeOneOutput(output, { adapted: true })).resolves.toBeUndefined()
  })

  it('rejects a static build instead of silently dropping APIs', async () => {
    const { output } = await fixture()
    await writeFile(join(output, 'nitro.json'), JSON.stringify({ preset: 'static', framework: { name: 'nuxt' } }))
    await expect(verifyEdgeOneOutput(output)).rejects.toThrow('publishing only .output/public')
  })

  it('rejects a missing Nitro entry even when assets remain', async () => {
    const { output, server } = await fixture()
    await rm(join(server, 'index.mjs'))
    await expect(verifyEdgeOneOutput(output)).rejects.toThrow('full-stack output is incomplete')
  })

  it('requires runtime dependencies within the deployable server directory', async () => {
    const { output, root, server } = await fixture()
    const sdk = join(server, 'node_modules/@cloudbase/node-sdk')
    await rm(sdk, { recursive: true })
    await mkdir(join(root, 'external-sdk'))
    await writeFile(join(root, 'external-sdk/package.json'), '{}')
    await symlink(join(root, 'external-sdk'), sdk, process.platform === 'win32' ? 'junction' : 'dir')
    await expect(verifyEdgeOneOutput(output)).rejects.toThrow('full-stack output is incomplete')
  })

  it('rejects final routing that covers pages but leaves APIs unmatched', async () => {
    const { output, server } = await fixture({ adapted: true })
    await writeFile(join(server, 'config.json'), JSON.stringify({
      version: 3,
      routes: [{ handle: 'filesystem' }, { src: '^/(login|tabs/home)$' }],
    }))
    await expect(verifyEdgeOneOutput(output, { adapted: true })).rejects.toThrow('full-stack output is incomplete')
  })

  it('keeps private dotenv files out of adapter copying and deployment output', async () => {
    const { root, output, server } = await fixture()
    await writeFile(join(root, '.env.example'), 'EXAMPLE_ONLY=')
    await expect(assertNoDeploymentEnvFiles(root)).resolves.toBeUndefined()
    await writeFile(join(root, '.env.production'), 'PRIVATE_TEST_TOKEN=do-not-publish')
    await expect(assertNoDeploymentEnvFiles(root)).rejects.toThrow('private .env files')
    await writeFile(join(server, '.env'), 'PRIVATE_TEST_TOKEN=do-not-publish')
    await expect(verifyEdgeOneOutput(output)).rejects.toThrow('full-stack output is incomplete')
  })
})
