import { expect, test } from '@nuxt/test-utils/playwright'

test('serves a lightweight landing page and keeps the legacy Web app navigation', async ({ page }) => {
  await page.goto('/?showcase')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('带回你的云居')
  await expect(page.locator('script')).toHaveAttribute('src', '/landing/app.js')
  await expect(page.locator('ion-app')).toHaveCount(0)
  await page.getByRole('link', { name: '体验兼容网页版' }).click()
  await expect(page).toHaveURL(/\/tabs\/home/)
  const workshop = page.locator('#tab-button-apps')
  await expect(workshop).toBeVisible()
  await workshop.click()
  await expect(page).toHaveURL(/\/tabs\/apps/)
  await expect(workshop).toHaveClass(/tab-selected/)
  await page.goBack()
  await expect(page).toHaveURL(/\/tabs\/home/)
  await expect(page.locator('#tab-button-home')).toHaveClass(/tab-selected/)

  await page.goto('/')
  await expect(page).toHaveURL(/\/tabs\/home$/)
  await page.goto('/?showcase#download')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('带回你的云居')
  await expect(page.locator('#download')).toBeInViewport()

  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'standalone', { configurable: true, value: true })
  })
  await page.goto('/?showcase')
  await expect(page).toHaveURL(/\/tabs\/home$/)
})

test('keeps the cloud app flight and destination in view on a short phone', async ({ browser, baseURL }) => {
  const page = await browser.newPage({
    baseURL,
    viewport: { width: 375, height: 667 },
    hasTouch: true,
    reducedMotion: 'no-preference',
  })
  try {
    await page.goto('/')
    const collect = page.getByRole('button', { name: '将云空调收进云居' })
    await collect.tap()

    const target = page.locator('#collectionSlots .dock-slot').first()
    await expect(page.locator('.flying-tile')).toBeInViewport({ ratio: 1 })
    await expect(target).toBeInViewport({ ratio: 1 })
    await expect(target).toHaveAccessibleName('打开云空调')
    await expect(page.getByRole('status').filter({ hasText: '已将「云空调」收进云居' })).toBeInViewport()

    await target.tap()
    await expect(page.getByRole('dialog', { name: '云空调' })).toBeInViewport({ ratio: 1 })
    await page.getByRole('button', { name: '返回云居' }).tap()
    await expect(target).toBeFocused()
  }
  finally {
    await page.close()
  }
})
