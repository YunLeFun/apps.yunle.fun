import { expect, test } from '@nuxt/test-utils/playwright'

test('keeps the Ionic tab stack and browser history after opening the Web app', async ({ page }) => {
  await page.goto('/?showcase')
  await page.getByText('打开网页版', { exact: true }).first().click()
  await expect(page).toHaveURL(/\/tabs\/home/)
  const workshop = page.locator('#tab-button-apps')
  await expect(workshop).toBeVisible()
  await workshop.click()
  await expect(page).toHaveURL(/\/tabs\/apps/)
  await expect(workshop).toHaveClass(/tab-selected/)
  await page.goBack()
  await expect(page).toHaveURL(/\/tabs\/home/)
  await expect(page.locator('#tab-button-home')).toHaveClass(/tab-selected/)
})
