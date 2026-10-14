import type { ConfigOptions } from '@nuxt/test-utils/playwright'
import process from 'node:process'
import { fileURLToPath } from 'node:url'
import { defineConfig, devices } from '@playwright/test'

export default defineConfig<ConfigOptions>({
  testDir: './test/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  // Nuxt's Playwright fixture builds an isolated app per worker. Running these
  // builds concurrently can exhaust local/CI resources before the tests start.
  workers: 1,
  reporter: process.env.CI ? 'line' : 'html',

  use: {
    baseURL: 'http://localhost:8001',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',

    nuxt: {
      rootDir: fileURLToPath(new URL('.', import.meta.url)),
    },
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },
  ],

  webServer: {
    command: 'pnpm dev',
    url: 'http://localhost:8001',
    reuseExistingServer: !process.env.CI,
  },
})
