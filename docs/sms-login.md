# 短信验证码登录功能

本项目已集成云开发（CloudBase）短信验证码登录功能。

## 功能说明

基于 [CloudBase 短信登录文档](https://docs.cloudbase.net/authentication-v2/method/sms-login) 实现的短信验证码登录功能。

### 重要说明

根据官方文档，CloudBase 短信登录使用以下 API：

1. **发送验证码**：`auth.getVerification({ phone_number: "+86 13800000000" })`
2. **验证码登录**：`auth.signInWithSms({ verificationInfo, verificationCode, phoneNum })`

注意：

- 手机号需要加区号，格式为 `+86 手机号`
- 如果手机号未注册，需要先调用 `auth.signUp()` 进行注册
- 当前实现仅支持已注册用户的登录功能

## 实现文件

### 1. Composable: `app/composables/wx/useSmsLogin.ts`（简单版）

提供短信登录的核心逻辑（仅支持已注册用户登录）：

- `sendVerifyCode()` - 发送短信验证码
- `loginWithSms()` - 使用手机号和验证码登录
- `initCloudBase()` - 初始化 CloudBase SDK

**主要功能：**

- 手机号格式验证（支持中国大陆手机号）
- 验证码发送倒计时（60秒）
- 自动清理定时器
- 错误处理和提示

### 1.1 Composable: `app/composables/wx/useSmsAuth.ts`（完整版）

提供完整的短信注册和登录功能：

- `sendVerifyCode()` - 发送短信验证码
- `loginWithSms()` - 已注册用户登录
- `signUp()` - 新用户注册
- `autoSignInOrUp()` - 自动判断登录或注册
- `verifyCode()` - 验证验证码

**主要功能：**

- 支持新用户注册（可设置昵称、密码、用户名）
- 支持已有用户登录
- 自动判断用户是否已注册
- 完整的错误处理

### 2. 组件: `app/components/SmsLogin.vue`（简单版）

短信登录 UI 组件（仅支持已注册用户）：

- 手机号输入框（限制11位）
- 验证码输入框（限制6位）
- 获取验证码按钮（带倒计时）
- 登录按钮
- 错误和成功提示

### 2.1 组件: `app/components/SmsAuthComplete.vue`（完整版）

完整的短信注册/登录 UI 组件：

- 手机号输入框
- 验证码输入框
- 获取验证码按钮（带倒计时）
- 新用户注册字段（昵称、密码）
- 自动判断登录或注册
- 错误和成功提示

### 3. 插件: `app/plugins/cloudbase.client.ts`

自动加载 CloudBase SDK（仅客户端）：

- 通过 CDN 动态加载 CloudBase SDK
- 避免重复加载
- 异步加载，不阻塞页面渲染

### 4. 集成到登录页面: `app/components/UserLogin.vue`

在现有登录页面添加了登录方式切换：

- 微信登录（原有功能）
- 短信登录（新增功能）

## 使用方法

### 在登录页面使用

登录页面 (`/login`) 已经集成了短信登录功能，用户可以：

1. 点击"短信登录"标签切换到短信登录模式
2. 输入手机号
3. 点击"获取验证码"按钮
4. 输入收到的验证码
5. 点击"登录"按钮完成登录

### 在其他页面使用

如果需要在其他页面使用短信登录功能，可以直接使用 `SmsLogin` 组件：

```vue
<script setup>
function handleLoginSuccess(user) {
  console.log('登录成功:', user)
  // 处理登录成功后的逻辑
}
</script>

<template>
  <SmsLogin @success="handleLoginSuccess" />
</template>
```

### 直接使用 Composable

**简单版（仅登录）：**

```vue
<script setup>
import { useSmsLogin } from '~/composables/wx/useSmsLogin'

const {
  phoneNumber,
  verifyCode,
  sendingCode,
  loggingIn,
  countdown,
  sendVerifyCode,
  loginWithSms,
} = useSmsLogin()

async function handleLogin() {
  const result = await loginWithSms()
  if (result.success) {
    console.log('登录成功:', result.user)
  }
}
</script>
```

**完整版（支持注册和登录）：**

```vue
<script setup>
import { useSmsAuth } from '~/composables/wx/useSmsAuth'

const {
  phoneNumber,
  verifyCode,
  password,
  nickname,
  sendVerifyCode,
  autoSignInOrUp,
} = useSmsAuth()

async function handleSubmit() {
  // 自动判断是登录还是注册
  const result = await autoSignInOrUp()
  if (result.success) {
    console.log('成功:', result.user)
  }
}
</script>
```

## 配置说明

### CloudBase 环境 ID

当前使用的环境 ID 为：`yunlefun-2g70u1n789fdeb60`

如需修改，请在以下文件中更新：

- `app/composables/wx/useSmsLogin.ts`
- `app/composables/wx/useCloudBase.ts`

### 短信模板配置

在使用短信登录前，需要在 [CloudBase 控制台](https://console.cloud.tencent.com/tcb) 进行以下配置：

1. 开启短信登录功能
2. 配置短信模板
3. 设置短信签名
4. 配置安全域名

详细配置步骤请参考：[CloudBase 短信登录配置](https://docs.cloudbase.net/authentication-v2/method/sms-login#%E9%85%8D%E7%BD%AE%E7%9F%AD%E4%BF%A1%E7%99%BB%E5%BD%95)

## 注意事项

1. **CloudBase SDK 加载**：SDK 通过 CDN 动态加载，首次使用时可能需要等待加载完成
2. **手机号格式**：目前仅支持中国大陆手机号（1开头的11位数字），发送时会自动添加 `+86` 区号
3. **验证码有效期**：验证码通常有效期为5分钟，请及时使用
4. **发送频率限制**：
   - 同一号码 30 秒内最多发送 1 条
   - 同一手机号一个自然日最多发送 10 条
   - 客户端实现了 60 秒的冷却时间
5. **安全性**：请确保在 CloudBase 控制台配置了正确的安全域名
6. **用户注册**：当前实现仅支持已注册用户登录，如需支持新用户注册，需要额外实现 `auth.signUp()` 流程

## 错误处理

常见错误及解决方案：

- **"CloudBase SDK 未加载"**：等待页面完全加载后再尝试
- **"手机号格式不正确"**：检查手机号是否为11位数字且以1开头
- **"发送验证码失败"**：检查 CloudBase 控制台配置是否正确
- **"登录失败"**：检查验证码是否正确，是否已过期

## 开发调试

在开发环境中，可以通过浏览器控制台查看详细的日志信息：

```javascript
// 查看 CloudBase 实例
console.log(window.cloudbase)

// 查看登录状态
const app = cloudbase.init({ env: 'yunlefun-2g70u1n789fdeb60' })
const auth = app.auth()
auth.getLoginState().then(console.log)
```

## 相关链接

- [CloudBase 短信登录文档](https://docs.cloudbase.net/authentication-v2/method/sms-login)
- [CloudBase 控制台](https://console.cloud.tencent.com/tcb)
- [CloudBase JS SDK 文档](https://docs.cloudbase.net/api-reference/webv3/initialization)
