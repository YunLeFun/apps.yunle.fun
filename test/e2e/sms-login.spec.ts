import { expect, test } from '@nuxt/test-utils/playwright'

test.describe('短信验证码登录', () => {
  test.beforeEach(async ({ page }) => {
    // 访问测试页面
    await page.goto('/test-sms')
  })

  test('应该显示短信登录表单', async ({ page }) => {
    // 检查页面标题
    await expect(page.locator('h1')).toContainText('短信登录测试')

    // 检查表单元素
    await expect(page.locator('input[type="tel"]')).toBeVisible()
    await expect(page.locator('input[type="text"]')).toBeVisible()
    await expect(page.locator('button:has-text("获取验证码")')).toBeVisible()
    await expect(page.locator('button:has-text("登录")')).toBeVisible()
  })

  test('应该验证手机号格式', async ({ page }) => {
    // 输入无效的手机号
    await page.fill('input[type="tel"]', '123')

    // 点击获取验证码
    await page.click('button:has-text("获取验证码")')

    // 应该显示错误消息
    await expect(page.locator('text=手机号格式不正确')).toBeVisible()
  })

  test('应该能够切换登录版本', async ({ page }) => {
    // 检查版本切换按钮
    await expect(page.locator('button:has-text("完整版")')).toBeVisible()
    await expect(page.locator('button:has-text("简单版")')).toBeVisible()

    // 切换到简单版
    await page.click('button:has-text("简单版")')

    // 验证切换成功（简单版不应该有昵称和密码字段）
    await expect(page.locator('input[placeholder*="昵称"]')).not.toBeVisible()
  })

  test('应该显示倒计时', async ({ page }) => {
    // Mock CloudBase SDK
    await page.addScriptTag({
      content: `
        window.cloudbase = {
          init: () => ({
            auth: () => ({
              getVerification: async () => ({
                verification_id: 'test-id',
                is_user: true
              }),
              signInWithSms: async () => ({}),
              getLoginState: async () => ({
                user: { uid: 'test-uid' }
              })
            })
          })
        };
      `,
    })

    // 输入有效的手机号
    await page.fill('input[type="tel"]', '13800000000')

    // 点击获取验证码
    await page.click('button:has-text("获取验证码")')

    // 等待一下让倒计时开始
    await page.waitForTimeout(100)

    // 应该显示倒计时
    await expect(page.locator('button:has-text("s")')).toBeVisible()
  })

  test('完整版应该显示注册字段', async ({ page }) => {
    // Mock CloudBase SDK - 返回新用户
    await page.addScriptTag({
      content: `
        window.cloudbase = {
          init: () => ({
            auth: () => ({
              getVerification: async () => ({
                verification_id: 'test-id',
                is_user: false  // 新用户
              }),
              verify: async () => ({
                verification_token: 'test-token'
              }),
              signUp: async () => ({}),
              getLoginState: async () => ({
                user: { uid: 'test-uid' }
              })
            })
          })
        };
      `,
    })

    // 确保在完整版
    await page.click('button:has-text("完整版")')

    // 输入手机号
    await page.fill('input[type="tel"]', '13900000000')

    // 点击获取验证码
    await page.click('button:has-text("获取验证码")')

    // 等待验证码发送成功
    await page.waitForTimeout(500)

    // 应该显示注册字段
    await expect(page.locator('input[placeholder*="昵称"]')).toBeVisible()
    await expect(page.locator('input[type="password"]')).toBeVisible()
  })

  test('应该禁用空表单的提交', async ({ page }) => {
    const loginButton = page.locator('button:has-text("登录")')

    // 登录按钮应该被禁用
    await expect(loginButton).toBeDisabled()

    // 输入手机号
    await page.fill('input[type="tel"]', '13800000000')

    // 仍然应该被禁用（缺少验证码）
    await expect(loginButton).toBeDisabled()

    // 输入验证码
    await page.fill('input[type="text"]', '123456')

    // 现在应该可以点击（但可能因为没有 verificationInfo 而失败）
    // 这里只测试 UI 状态
    await expect(loginButton).not.toBeDisabled()
  })

  test('应该限制手机号输入长度', async ({ page }) => {
    const phoneInput = page.locator('input[type="tel"]')

    // 输入超过11位的手机号
    await phoneInput.fill('138000000001234')

    // 应该只保留11位
    const value = await phoneInput.inputValue()
    expect(value.length).toBeLessThanOrEqual(11)
  })

  test('应该限制验证码输入长度', async ({ page }) => {
    const codeInput = page.locator('input[type="text"]')

    // 输入超过6位的验证码
    await codeInput.fill('12345678')

    // 应该只保留6位
    const value = await codeInput.inputValue()
    expect(value.length).toBeLessThanOrEqual(6)
  })

  test('应该显示成功消息', async ({ page }) => {
    // Mock CloudBase SDK
    await page.addScriptTag({
      content: `
        window.cloudbase = {
          init: () => ({
            auth: () => ({
              getVerification: async () => ({
                verification_id: 'test-id',
                is_user: true
              }),
              signInWithSms: async () => ({}),
              getLoginState: async () => ({
                user: { 
                  uid: 'test-uid',
                  phone: '13800000000'
                }
              })
            })
          })
        };
      `,
    })

    // 输入手机号
    await page.fill('input[type="tel"]', '13800000000')

    // 获取验证码
    await page.click('button:has-text("获取验证码")')
    await page.waitForTimeout(500)

    // 输入验证码
    await page.fill('input[type="text"]', '123456')

    // 点击登录
    await page.click('button:has-text("登录")')

    // 等待登录完成
    await page.waitForTimeout(1000)

    // 应该显示成功页面
    await expect(page.locator('text=登录成功')).toBeVisible()
  })
})

test.describe('登录页面集成', () => {
  test('应该在登录页面显示短信登录选项', async ({ page }) => {
    await page.goto('/login')

    // 应该有登录方式切换
    await expect(page.locator('button:has-text("微信登录")')).toBeVisible()
    await expect(page.locator('button:has-text("短信登录")')).toBeVisible()
  })

  test('应该能够切换到短信登录', async ({ page }) => {
    await page.goto('/login')

    // 点击短信登录
    await page.click('button:has-text("短信登录")')

    // 应该显示短信登录表单
    await expect(page.locator('input[type="tel"]')).toBeVisible()
    await expect(page.locator('button:has-text("获取验证码")')).toBeVisible()
  })
})
