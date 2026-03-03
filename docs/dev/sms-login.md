# 短信登录

基于 [CloudBase 短信登录](https://docs.cloudbase.net/authentication-v2/method/sms-login) 实现。

## API 说明

1. **发送验证码**：`auth.getVerification({ phone_number: "+86 13800000000" })`
2. **验证码登录**：`auth.signInWithSms({ verificationInfo, verificationCode, phoneNum })`

::: tip
手机号需要加区号，格式为 `+86 手机号`。如果手机号未注册，需要先调用 `auth.signUp()` 进行注册。
:::

## 实现方案

### 简单版（仅登录）

`app/composables/wx/useSmsLogin.ts`

```vue
<script setup>
import { useSmsLogin } from '~/composables/wx/useSmsLogin'

const {
  phoneNumber,
  verifyCode,
  countdown,
  sendVerifyCode,
  loginWithSms,
} = useSmsLogin()
</script>
```

### 完整版（注册 + 登录）

`app/composables/wx/useSmsAuth.ts`

```vue
<script setup>
import { useSmsAuth } from '~/composables/wx/useSmsAuth'

const {
  phoneNumber,
  verifyCode,
  sendVerifyCode,
  autoSignInOrUp,
} = useSmsAuth()
</script>
```

## 配置

- CloudBase 环境 ID：`yunlefun-2g70u1n789fdeb60`
- 在 [CloudBase 控制台](https://console.cloud.tencent.com/tcb) 开启短信登录并配置短信模板

## 注意事项

- 同一号码 30 秒内最多发送 1 条
- 同一手机号一个自然日最多发送 10 条
- 客户端实现了 60 秒冷却时间
- 验证码有效期约 5 分钟
