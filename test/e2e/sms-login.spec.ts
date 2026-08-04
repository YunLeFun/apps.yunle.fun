import { expect, test } from '@nuxt/test-utils/playwright'

test.describe('登录页面', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/login')
  })

  test('默认展示当前支持的手机号登录方式', async ({ page }) => {
    await expect(page.getByRole('heading', { name: '登录' })).toBeVisible()
    await expect(page.getByRole('button', { name: '手机号' })).toBeVisible()
    await expect(page.getByRole('button', { name: '邮箱' })).toBeVisible()
    await expect(page.getByRole('button', { name: '密码' })).toBeVisible()

    await expect(page.getByPlaceholder('请输入手机号')).toBeVisible()
    await expect(page.getByRole('button', { name: '获取验证码' })).toBeDisabled()

    await expect(page.getByRole('button', { name: 'GitHub' })).toHaveCount(0)
    await expect(page.getByRole('button', { name: '微信' })).toHaveCount(0)
  })

  test('可以切换邮箱和密码登录', async ({ page }) => {
    await page.getByRole('button', { name: '邮箱' }).click()
    await expect(page.getByPlaceholder('请输入您的邮箱')).toBeVisible()
    await expect(page.getByText('邮箱仅支持已绑定的用户登录')).toBeVisible()

    await page.getByRole('button', { name: '密码' }).click()
    await expect(page.getByPlaceholder('手机号 / 邮箱 / 用户名')).toBeVisible()
    await expect(page.getByPlaceholder('请输入密码')).toBeVisible()
    await expect(page.getByRole('button', { name: '登录', exact: true })).toBeDisabled()
  })

  test('允许已有的长用户名进行密码登录', async ({ page }) => {
    await page.getByRole('button', { name: '密码' }).click()
    await page.getByPlaceholder('手机号 / 邮箱 / 用户名').fill('ylf_test_saier_viewer')
    await page.getByPlaceholder('请输入密码').fill('test-password')

    await expect(page.getByRole('button', { name: '登录', exact: true })).toBeEnabled()
  })

  test('限制手机号长度并支持切换注册模式', async ({ page }) => {
    const phoneInput = page.getByPlaceholder('请输入手机号')
    await phoneInput.fill('138000000001234')
    await expect(phoneInput).toHaveValue('13800000000')
    await expect(page.getByRole('button', { name: '获取验证码' })).toBeEnabled()

    await page.getByRole('button', { name: '立即注册' }).click()
    await expect(page.getByRole('heading', { name: '创建账号' })).toBeVisible()
    await expect(page.getByPlaceholder('请输入手机号')).toBeVisible()
    await expect(page.getByRole('button', { name: '获取验证码' })).toBeDisabled()
    await expect(page.getByRole('button', { name: '立即登录' })).toBeVisible()
  })

  test('展示可访问的服务条款与隐私政策入口', async ({ page }) => {
    await expect(page.getByRole('link', { name: '服务条款' })).toBeVisible()
    await expect(page.getByRole('link', { name: '隐私政策' })).toBeVisible()
  })
})
