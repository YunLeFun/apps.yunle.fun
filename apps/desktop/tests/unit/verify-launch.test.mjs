import { Buffer } from 'node:buffer'
import { EventEmitter } from 'node:events'
import process from 'node:process'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const mocks = vi.hoisted(() => ({
  spawn: vi.fn(),
  rm: vi.fn(),
}))
vi.mock('node:child_process', () => ({ spawn: mocks.spawn }))
vi.mock('node:fs/promises', () => ({ default: {
  readFile: async () => JSON.stringify({ productName: '云乐坊' }),
  readdir: async () => [`云乐坊-${process.platform}-${process.arch}`],
  mkdtemp: async () => '/test-profile',
  rm: mocks.rm,
} }))
vi.mock('../../scripts/lib.mjs', () => ({ root: '/desktop' }))

class Child extends EventEmitter {
  pid = 100000
  exitCode = null
  signalCode = null
  stdout = new EventEmitter()
  stderr = new EventEmitter()
  kill = vi.fn((signal) => {
    if (this.exitCode !== null || this.signalCode !== null)
      return false
    queueMicrotask(() => this.exit(null, signal))
    return true
  })

  exit(code, signal = null) {
    this.exitCode = code
    this.signalCode = signal
    this.emit('exit', code, signal)
  }
}

beforeEach(() => {
  vi.resetModules()
  vi.resetAllMocks()
  vi.spyOn(console, 'info').mockImplementation(() => {})
})

afterEach(() => {
  vi.restoreAllMocks()
})

// Bound the whole script, including finally: an already emitted signal exit
// must report the launch failure rather than await another exit forever.
async function runLaunch() {
  let timer
  try {
    return await Promise.race([
      import('../../scripts/verify-launch.mjs').then(() => 'ready', error => error.message),
      new Promise(resolve => timer = setTimeout(resolve, 1000, 'startup check hung during cleanup')),
    ])
  }
  finally {
    clearTimeout(timer)
  }
}

describe('native packaged startup verification', () => {
  it('reports a signalled crash and removes the profile without waiting on a dead process', async () => {
    const child = new Child()
    mocks.spawn.mockImplementation(() => {
      queueMicrotask(() => {
        child.stderr.emit('data', Buffer.from('sandbox failed'))
        child.exit(null, 'SIGSEGV')
      })
      return child
    })
    expect(await runLaunch()).toBe('Packaged app exited (SIGSEGV): sandbox failed')
    expect(child.kill).not.toHaveBeenCalled()
    expect(mocks.rm).toHaveBeenCalledWith('/test-profile', expect.objectContaining({ recursive: true, force: true }))
  })

  it('handles an exit immediately after readiness without killing the already terminated app', async () => {
    const child = new Child()
    mocks.spawn.mockImplementation(() => {
      queueMicrotask(() => {
        child.stdout.emit('data', Buffer.from('[desktop] ready: app://shell'))
        child.exit(null, 'SIGTERM')
      })
      return child
    })
    expect(await runLaunch()).toBe('ready')
    expect(child.kill).not.toHaveBeenCalled()
    expect(mocks.rm).toHaveBeenCalledOnce()
  })

  it('stops a running ready app before removing its temporary profile', async () => {
    const child = new Child()
    mocks.spawn.mockImplementation(() => {
      queueMicrotask(() => child.stdout.emit('data', Buffer.from('[desktop] ready: app://shell')))
      return child
    })
    mocks.rm.mockImplementation(async () => {
      expect(child.signalCode).toBe('SIGTERM')
    })
    expect(await runLaunch()).toBe('ready')
    expect(child.kill).toHaveBeenCalledWith('SIGTERM')
  })
})
