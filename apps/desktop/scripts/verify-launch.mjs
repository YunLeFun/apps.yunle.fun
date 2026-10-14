import { spawn } from 'node:child_process'
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import process from 'node:process'
import { root } from './lib.mjs'

const metadata = JSON.parse(await fs.readFile(path.join(root, 'package.json'), 'utf8'))
const target = (await fs.readdir(path.join(root, 'out'))).find(name => name.endsWith(`-${process.platform}-${process.arch}`))
if (!target)
  throw new Error('No native packaged app found. Run pnpm package first.')
const directory = path.join(root, 'out', target)
const executable = process.platform === 'darwin'
  ? path.join(directory, `${metadata.productName}.app/Contents/MacOS/YunLeFun`)
  : path.join(directory, `YunLeFun${process.platform === 'win32' ? '.exe' : ''}`)
const userData = await fs.mkdtemp(path.join(os.tmpdir(), 'yunle-desktop-packaged-'))
const env = { ...process.env }
for (const name of ['ELECTRON_RUN_AS_NODE', 'NODE_OPTIONS', 'YUNLE_DESKTOP_DEV_ORIGIN', 'YUNLE_DESKTOP_TEST_ORIGIN', 'YUNLE_DESKTOP_E2E'])
  delete env[name]
let child
try {
  await new Promise((resolve, reject) => {
    let output = ''
    const timer = setTimeout(() => reject(new Error(`Packaged app did not load its static shell:\n${output}`)), 30000)
    child = spawn(executable, [`--user-data-dir=${userData}`], { env, stdio: ['ignore', 'pipe', 'pipe'] })
    function receive(chunk) {
      output += chunk.toString()
      if (output.includes('[desktop] ready: app://shell')) {
        clearTimeout(timer)
        resolve()
      }
    }
    child.stdout.on('data', receive)
    child.stderr.on('data', receive)
    child.once('error', (error) => {
      clearTimeout(timer)
      reject(error)
    })
    child.once('exit', (code, signal) => {
      clearTimeout(timer)
      reject(new Error(`Packaged app exited (${signal || code}): ${output}`))
    })
  })
  console.info('Verified native packaged app startup, static shell and runtime dependencies.')
}
finally {
  if (child?.pid && child.exitCode === null && child.signalCode === null) {
    const exited = new Promise(resolve => child.once('exit', resolve))
    child.kill('SIGTERM')
    const timer = setTimeout(() => child.kill('SIGKILL'), 5000)
    await exited
    clearTimeout(timer)
  }
  await fs.rm(userData, { recursive: true, force: true })
}
