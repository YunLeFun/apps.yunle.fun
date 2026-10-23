import type { ElectronApplication, TestInfo } from '@playwright/test'
import type { Server } from 'node:http'
import fs from 'node:fs/promises'
import { expect } from '@playwright/test'

export async function cleanupElectronTest(options: {
  application: ElectronApplication | undefined
  testInfo: TestInfo
  server: Server
  userData: string
  failed: boolean
}) {
  const { application, testInfo, server, userData, failed } = options
  // Electron/macOS shutdown can vary independently of the UI assertions.
  // Extend the budget only once assertions have finished; keep natural app.close().
  testInfo.setTimeout(testInfo.timeout + 60_000)
  const errors: unknown[] = []
  async function attempt(action: () => Promise<void>) {
    try {
      await action()
    }
    catch (error) {
      errors.push(error)
    }
  }
  await attempt(async () => {
    if (!application)
      return
    if (failed || testInfo.status !== testInfo.expectedStatus) {
      const trace = testInfo.outputPath('electron-trace.zip')
      await application.context().tracing.stop({ path: trace })
      await testInfo.attach('Electron trace', { path: trace, contentType: 'application/zip' })
    }
    else {
      await application.context().tracing.stop()
    }
  })
  await attempt(async () => {
    if (!application)
      return
    const child = application.process()
    const started = Date.now()
    await application.close()
    const result = {
      elapsedMs: Date.now() - started,
      exitCode: child.exitCode,
      signalCode: child.signalCode,
    }
    // eslint-disable-next-line no-console -- Preserve evidence of natural process termination.
    console.info('[desktop] Electron natural exit:', JSON.stringify(result))
    await testInfo.attach('Electron natural exit', { body: JSON.stringify(result), contentType: 'application/json' })
    expect(result.exitCode).toBe(0)
  })
  await attempt(() => new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve())))
  await attempt(() => fs.rm(userData, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 }))
  if (!errors.length)
    return
  if (failed) {
    for (const error of errors)
      console.warn('Electron test cleanup failed after the original test failure:', error)
    return
  }
  throw new AggregateError(errors, 'Electron test cleanup failed')
}
