<script lang="ts" setup>
import type { TcbOtpData, TcbSignUpData } from '~/composables/auth/useCloudbaseOtp'
import {
  IonBackButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonPage,
  IonSpinner,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { isValidEmail, isValidPhone, useCountdown } from '@yunlefun/auth'
import { eyeOffOutline, eyeOutline, logoGithub, logoWechat } from 'ionicons/icons'
import { config } from '~/config'
import { authMethods, getEnabledLoginTabs, hasEnabledOAuthProviders } from '~/config/auth'

// 用户名校验正则：小写字母开头，包含字母数字下划线连字符，3-20 字符
const USERNAME_REGEX = /^[a-z][\w-]{2,19}$/i

const {
  sendPhoneOtp,
  verifyPhoneOtp,
  sendEmailOtp,
  verifyEmailOtp,
  signUpWithPhone,
  verifySignUpOtp,
  signInWithPassword,
  loginWithGitHub,
  loginWithWeChat,
  loading,
  isAuthenticated,
} = useCloudbaseAuth()

const router = useRouter()
const accountsStore = useAccountsStore()

watch(isAuthenticated, (value) => {
  if (value) {
    router.push('/tabs/me')
  }
}, { immediate: true })

// 页面模式：登录 / 注册
type PageMode = 'login' | 'signup'
const pageMode = ref<PageMode>('login')

// 登录方式配置
const loginTabs = getEnabledLoginTabs()

// 登录方式切换
type LoginMode = 'phone' | 'email' | 'password'
const loginMode = ref<LoginMode>(loginTabs[0]?.key as LoginMode || 'phone')

// 手机号登录状态
const phone = ref('')
const phoneOtpCode = ref('')
const phoneOtpData = ref<TcbOtpData | null>(null)
const phoneCodeSent = ref(false)
const { remaining: phoneCountdown, isActive: phoneCountdownActive, start: startPhoneCountdown } = useCountdown()

// 邮箱登录状态
const email = ref('')
const emailOtpCode = ref('')
const emailOtpData = ref<TcbOtpData | null>(null)
const emailCodeSent = ref(false)
const { remaining: emailCountdown, isActive: emailCountdownActive, start: startEmailCountdown } = useCountdown()

// 密码登录状态
const LAST_PASSWORD_ACCOUNT_KEY = 'ylf_last_password_account'
const passwordAccount = ref('')
const passwordValue = ref('')
const showPassword = ref(false)
const isPasswordEmail = computed(() => isValidEmail(passwordAccount.value))
const isPasswordPhone = computed(() => isValidPhone(passwordAccount.value))
const isPasswordUsername = computed(() => USERNAME_REGEX.test(passwordAccount.value))
const passwordFormValid = computed(() =>
  (isPasswordEmail.value || isPasswordPhone.value || isPasswordUsername.value) && passwordValue.value.length >= 6,
)

// 注册状态
const signupPhone = ref('')
const signupOtpCode = ref('')
const signupData = ref<TcbSignUpData | null>(null)
const signupCodeSent = ref(false)
const { remaining: signupCountdown, isActive: signupCountdownActive, start: startSignupCountdown } = useCountdown()

// 恢复上次登录信息
onMounted(() => {
  // 恢复上次密码登录的账号
  const saved = localStorage.getItem(LAST_PASSWORD_ACCOUNT_KEY)
  if (saved)
    passwordAccount.value = saved

  // 恢复上次手机号
  if (accountsStore.lastPhone)
    phone.value = accountsStore.lastPhone
})

// 校验
const phoneValid = computed(() => isValidPhone(phone.value))
const emailValid = computed(() => isValidEmail(email.value))
const signupPhoneValid = computed(() => isValidPhone(signupPhone.value))

// 切换页面模式时重置状态
function switchMode(mode: PageMode) {
  pageMode.value = mode
}

// 手机号验证码
async function handleSendPhoneOtp() {
  if (!phoneValid.value)
    return
  try {
    // 记住手机号
    accountsStore.rememberPhone(phone.value)
    phoneOtpData.value = await sendPhoneOtp(phone.value)
    phoneCodeSent.value = true
    startPhoneCountdown()
  }
  catch {}
}

async function handleVerifyPhoneOtp() {
  if (!phoneOtpData.value || !phoneOtpCode.value)
    return
  try {
    await verifyPhoneOtp(phoneOtpData.value, phoneOtpCode.value)
    // 登录成功后保存账号
    afterLoginSuccess('phone')
  }
  catch {}
}

// 邮箱验证码
async function handleSendEmailOtp() {
  if (!emailValid.value)
    return
  try {
    emailOtpData.value = await sendEmailOtp(email.value)
    emailCodeSent.value = true
    startEmailCountdown()
  }
  catch {}
}

async function handleVerifyEmailOtp() {
  if (!emailOtpData.value || !emailOtpCode.value)
    return
  try {
    await verifyEmailOtp(emailOtpData.value, emailOtpCode.value)
    afterLoginSuccess('email')
  }
  catch {}
}

// 密码登录
async function handlePasswordLogin() {
  if (!passwordFormValid.value)
    return
  try {
    const params: { email?: string, phone?: string, username?: string, password: string } = { password: passwordValue.value }
    if (isPasswordEmail.value)
      params.email = passwordAccount.value
    else if (isPasswordPhone.value)
      params.phone = passwordAccount.value
    else
      params.username = passwordAccount.value
    await signInWithPassword(params)
    // 登录成功，记住账号
    localStorage.setItem(LAST_PASSWORD_ACCOUNT_KEY, passwordAccount.value)
    afterLoginSuccess('password')
  }
  catch {}
}

// 手机号注册
async function handleSendSignupOtp() {
  if (!signupPhoneValid.value)
    return
  try {
    signupData.value = await signUpWithPhone(signupPhone.value)
    signupCodeSent.value = true
    startSignupCountdown()
  }
  catch {}
}

async function handleVerifySignupOtp() {
  if (!signupData.value || !signupOtpCode.value)
    return
  try {
    await verifySignUpOtp(signupData.value, signupOtpCode.value)
    afterLoginSuccess('phone')
  }
  catch {}
}

/**
 * 登录/注册成功后保存账号信息
 */
function afterLoginSuccess(method: 'phone' | 'email' | 'password' | 'github' | 'wechat') {
  const userStore = useUserStore()
  if (userStore.userInfo) {
    accountsStore.saveAccount(userStore.userInfo, method)
  }
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" text="返回" />
        </IonButtons>
        <IonTitle>{{ pageMode === 'login' ? '登录' : '注册' }}</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true" class="ion-padding">
      <div class="auth-container">
        <!-- Logo 区域 -->
        <div class="auth-header">
          <YlfLogoSvg class="auth-logo-icon" />
          <p class="auth-brand">
            云乐坊
          </p>
          <h1 class="auth-title">
            {{ pageMode === 'login' ? '登录' : '创建账号' }}
          </h1>
        </div>

        <!-- ===== 登录模式 ===== -->
        <template v-if="pageMode === 'login'">
          <!-- Segmented Control（根据开关配置动态渲染） -->
          <div v-if="loginTabs.length > 1" class="auth-segment">
            <button
              v-for="tab in loginTabs"
              :key="tab.key"
              class="auth-segment-btn"
              :class="{ active: loginMode === tab.key }"
              @click="loginMode = tab.key as LoginMode"
            >
              {{ tab.label }}
            </button>
          </div>

          <!-- 手机号登录 -->
          <div v-if="loginMode === 'phone' && authMethods.phoneOtp" class="auth-form">
            <div class="auth-card">
              <div class="auth-card-row">
                <span class="auth-area-code">+86</span>
                <div class="auth-card-divider" />
                <input
                  v-model="phone"
                  type="tel"
                  placeholder="请输入手机号"
                  class="auth-input"
                  maxlength="11"
                  :disabled="loading"
                  @keyup.enter="phoneCodeSent ? handleVerifyPhoneOtp() : handleSendPhoneOtp()"
                >
              </div>
              <template v-if="phoneCodeSent">
                <div class="auth-card-separator" />
                <div class="auth-card-row">
                  <input
                    v-model="phoneOtpCode"
                    type="text"
                    inputmode="numeric"
                    placeholder="输入 6 位验证码"
                    class="auth-input"
                    maxlength="6"
                    :disabled="loading"
                    @keyup.enter="handleVerifyPhoneOtp()"
                  >
                  <button
                    class="auth-inline-action"
                    :disabled="phoneCountdownActive || loading"
                    @click="handleSendPhoneOtp"
                  >
                    {{ phoneCountdownActive ? `${phoneCountdown}s` : '重新发送' }}
                  </button>
                </div>
              </template>
            </div>

            <button
              v-if="phoneCodeSent"
              class="auth-btn-primary"
              :disabled="!phoneOtpCode || phoneOtpCode.length < 4 || loading"
              @click="handleVerifyPhoneOtp"
            >
              <IonSpinner v-if="loading" name="crescent" class="auth-btn-spinner" />
              <span v-else>登录</span>
            </button>
            <button
              v-else
              class="auth-btn-primary"
              :disabled="!phoneValid || loading"
              @click="handleSendPhoneOtp"
            >
              <IonSpinner v-if="loading" name="crescent" class="auth-btn-spinner" />
              <span v-else>获取验证码</span>
            </button>
          </div>

          <!-- 邮箱登录 -->
          <div v-else-if="loginMode === 'email' && authMethods.emailOtp" class="auth-form">
            <div class="auth-card">
              <div class="auth-card-row">
                <input
                  v-model="email"
                  type="email"
                  placeholder="请输入您的邮箱"
                  class="auth-input w-full"
                  :disabled="loading"
                  @keyup.enter="emailCodeSent ? handleVerifyEmailOtp() : handleSendEmailOtp()"
                >
              </div>
              <template v-if="emailCodeSent">
                <div class="auth-card-separator" />
                <div class="auth-card-row">
                  <input
                    v-model="emailOtpCode"
                    type="text"
                    inputmode="numeric"
                    placeholder="输入 6 位验证码"
                    class="auth-input"
                    maxlength="6"
                    :disabled="loading"
                    @keyup.enter="handleVerifyEmailOtp()"
                  >
                  <button
                    class="auth-inline-action"
                    :disabled="emailCountdownActive || loading"
                    @click="handleSendEmailOtp"
                  >
                    {{ emailCountdownActive ? `${emailCountdown}s` : '重新发送' }}
                  </button>
                </div>
              </template>
            </div>

            <button
              v-if="emailCodeSent"
              class="auth-btn-primary"
              :disabled="!emailOtpCode || emailOtpCode.length < 4 || loading"
              @click="handleVerifyEmailOtp"
            >
              <IonSpinner v-if="loading" name="crescent" class="auth-btn-spinner" />
              <span v-else>登录</span>
            </button>
            <button
              v-else
              class="auth-btn-primary"
              :disabled="!emailValid || loading"
              @click="handleSendEmailOtp"
            >
              <IonSpinner v-if="loading" name="crescent" class="auth-btn-spinner" />
              <span v-else>获取验证码</span>
            </button>

            <p class="auth-hint">
              邮箱仅支持已绑定的用户登录
            </p>
          </div>

          <!-- 密码登录 -->
          <form v-else class="auth-form" @submit.prevent="handlePasswordLogin">
            <div class="auth-card">
              <div class="auth-card-row">
                <input
                  v-model="passwordAccount"
                  type="text"
                  placeholder="手机号 / 邮箱 / 用户名"
                  class="auth-input w-full"
                  autocomplete="username"
                  :disabled="loading"
                >
              </div>
              <div class="auth-card-separator" />
              <div class="auth-card-row">
                <input
                  v-model="passwordValue"
                  :type="showPassword ? 'text' : 'password'"
                  placeholder="请输入密码"
                  class="auth-input"
                  autocomplete="current-password"
                  :disabled="loading"
                >
                <button
                  class="auth-inline-action"
                  type="button"
                  @click="showPassword = !showPassword"
                >
                  <IonIcon :icon="showPassword ? eyeOffOutline : eyeOutline" class="text-lg" />
                </button>
              </div>
            </div>

            <button
              type="submit"
              class="auth-btn-primary"
              :disabled="!passwordFormValid || loading"
            >
              <IonSpinner v-if="loading" name="crescent" class="auth-btn-spinner" />
              <span v-else>登录</span>
            </button>

            <p class="auth-hint">
              需先在账号安全设置中设置密码
            </p>
          </form>

          <!-- 分割线 -->
          <div v-if="hasEnabledOAuthProviders()" class="auth-divider">
            <span class="auth-divider-text">其他登录方式</span>
          </div>

          <!-- 第三方登录 - 图标模式 -->
          <div v-if="hasEnabledOAuthProviders()" class="auth-social-icons">
            <button v-if="authMethods.github" class="auth-social-circle auth-social-circle--github" :disabled="loading" @click="loginWithGitHub()">
              <IonIcon :icon="logoGithub" class="auth-social-circle-icon" />
              <span class="auth-social-circle-label">GitHub</span>
            </button>
            <button v-if="authMethods.wechat" class="auth-social-circle auth-social-circle--wechat" :disabled="loading" @click="loginWithWeChat()">
              <IonIcon :icon="logoWechat" class="auth-social-circle-icon" />
              <span class="auth-social-circle-label">微信</span>
            </button>
          </div>

          <!-- 注册入口 -->
          <div v-if="authMethods.phoneSignup" class="auth-footer">
            <p class="auth-footer-switch">
              还没有账号？
              <button class="auth-link-btn" @click="switchMode('signup')">
                立即注册
              </button>
            </p>
          </div>
        </template>

        <!-- ===== 注册模式 ===== -->
        <template v-if="pageMode === 'signup' && authMethods.phoneSignup">
          <div class="auth-form">
            <div class="auth-card">
              <div class="auth-card-row">
                <span class="auth-area-code">+86</span>
                <div class="auth-card-divider" />
                <input
                  v-model="signupPhone"
                  type="tel"
                  placeholder="请输入手机号"
                  class="auth-input"
                  maxlength="11"
                  :disabled="loading"
                  @keyup.enter="signupCodeSent ? handleVerifySignupOtp() : handleSendSignupOtp()"
                >
              </div>
              <template v-if="signupCodeSent">
                <div class="auth-card-separator" />
                <div class="auth-card-row">
                  <input
                    v-model="signupOtpCode"
                    type="text"
                    inputmode="numeric"
                    placeholder="输入 6 位验证码"
                    class="auth-input"
                    maxlength="6"
                    :disabled="loading"
                    @keyup.enter="handleVerifySignupOtp()"
                  >
                  <button
                    class="auth-inline-action"
                    :disabled="signupCountdownActive || loading"
                    @click="handleSendSignupOtp"
                  >
                    {{ signupCountdownActive ? `${signupCountdown}s` : '重新发送' }}
                  </button>
                </div>
              </template>
            </div>

            <button
              v-if="signupCodeSent"
              class="auth-btn-primary"
              :disabled="!signupOtpCode || signupOtpCode.length < 4 || loading"
              @click="handleVerifySignupOtp"
            >
              <IonSpinner v-if="loading" name="crescent" class="auth-btn-spinner" />
              <span v-else>注册</span>
            </button>
            <button
              v-else
              class="auth-btn-primary"
              :disabled="!signupPhoneValid || loading"
              @click="handleSendSignupOtp"
            >
              <IonSpinner v-if="loading" name="crescent" class="auth-btn-spinner" />
              <span v-else>获取验证码</span>
            </button>

            <p class="auth-hint">
              注册即表示您同意
              <a href="#" class="auth-link" @click.prevent="openInAppBrowser(config.legal.terms)">服务条款</a>
              和
              <a href="#" class="auth-link" @click.prevent="openInAppBrowser(config.legal.privacy)">隐私政策</a>
            </p>
          </div>

          <!-- 登录入口 -->
          <div class="auth-footer">
            <p class="auth-footer-switch">
              已有账号？
              <button class="auth-link-btn" @click="switchMode('login')">
                立即登录
              </button>
            </p>
          </div>
        </template>

        <!-- 底部服务条款（仅登录模式） -->
        <div v-if="pageMode === 'login'" class="auth-terms">
          <p class="auth-terms-text">
            登录即表示您同意
            <a href="#" class="auth-link" @click.prevent="openInAppBrowser(config.legal.terms)">服务条款</a>
            和
            <a href="#" class="auth-link" @click.prevent="openInAppBrowser(config.legal.privacy)">隐私政策</a>
          </p>
        </div>
      </div>
    </IonContent>
  </IonPage>
</template>

<style lang="scss" scoped>
.auth-container {
  max-width: 400px;
  margin: 0 auto;
  padding: 0 4px;
}

// Header
.auth-header {
  text-align: center;
  padding: 32px 0 28px;
}

.auth-logo-icon {
  width: 64px;
  height: 64px;
  margin: 0 auto 12px;
  color: var(--ion-text-color, #000);
}

.auth-brand {
  font-size: 15px;
  font-weight: 500;
  color: var(--ion-color-medium, #8e8e93);
  margin: 0 0 4px;
}

.auth-title {
  font-size: 32px;
  font-weight: 700;
  color: var(--ion-text-color, #000);
  margin: 0;
  letter-spacing: -0.5px;
}

// iOS Segmented Control — 对齐 UISegmentedControl 原生规范
.auth-segment {
  display: flex;
  background: var(--ylf-fill-secondary); // iOS systemGray5 等价语义色
  border-radius: 9px;
  padding: 2px;
  margin: 0 16px 20px;
}

.auth-segment-btn {
  flex: 1;
  padding: 7px 0;
  font-size: 13px;
  font-weight: 600;
  text-align: center;
  border: none;
  background: transparent;
  color: var(--ion-text-color, #000);
  border-radius: 7px;
  transition: all 0.2s cubic-bezier(0.25, 0.46, 0.45, 0.94);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;

  &.active {
    background: #fff; // 固定纯白，不受 --ion-background-color 重写影响
    box-shadow:
      0 0 0.5px rgba(0, 0, 0, 0.04),
      0 1px 4px rgba(0, 0, 0, 0.12); // iOS 原生阴影层级

    .dark & {
      background: #636366;
      color: #fff;
    }
  }

  &:not(.active) {
    opacity: 0.5;
  }
}

// Form
.auth-form {
  margin-bottom: 4px;
  padding: 0 16px;
}

// iOS Grouped Card — 浅色模式白色卡片 + 页面灰色背景形成区分（iOS 标准分组列表风格）
.auth-card {
  background: var(--ion-item-background);
  border-radius: 12px;
  overflow: hidden;
  margin-bottom: 16px;
}

.auth-card-row {
  display: flex;
  align-items: center;
  padding: 0 16px;
  min-height: 48px;
}

.auth-card-divider {
  width: 1px;
  height: 20px;
  background: var(--ylf-separator);
  margin: 0 12px 0 8px;
  flex-shrink: 0;
}

.auth-card-separator {
  height: 0.5px;
  background: var(--ylf-separator);
  margin-left: 16px;
}

.auth-area-code {
  font-size: 17px;
  font-weight: 400;
  color: var(--ion-text-color, #000);
  white-space: nowrap;
  flex-shrink: 0;
}

.auth-input {
  flex: 1;
  font-size: 17px;
  font-weight: 400;
  color: var(--ion-text-color, #000);
  background: transparent;
  border: none;
  outline: none;
  padding: 0;
  min-width: 0;
  height: 48px;
  line-height: 48px;

  &::placeholder {
    color: var(--ion-color-medium, #c7c7cc);
  }

  &:disabled {
    opacity: 0.4;
  }
}

.auth-inline-action {
  font-size: 15px;
  font-weight: 500;
  color: var(--ion-color-primary, #007aff);
  background: none;
  border: none;
  white-space: nowrap;
  cursor: pointer;
  padding: 4px 0;
  flex-shrink: 0;
  -webkit-tap-highlight-color: transparent;

  &:active {
    opacity: 0.5;
  }

  &:disabled {
    color: var(--ion-color-medium, #8e8e93);
    cursor: default;
  }
}

// Primary Button - iOS style
.auth-btn-primary {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  height: 50px;
  border-radius: 12px;
  border: none;
  background: var(--ion-color-primary, #007aff);
  color: #fff;
  font-size: 17px;
  font-weight: 600;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: opacity 0.15s ease;
  margin-bottom: 12px;

  &:active:not(:disabled) {
    opacity: 0.75;
  }

  &:disabled {
    opacity: 0.35;
    cursor: default;
  }
}

.auth-btn-spinner {
  width: 20px;
  height: 20px;
  color: #fff;
}

.auth-hint {
  font-size: 13px;
  color: var(--ion-color-medium, #8e8e93);
  text-align: center;
  margin-top: 4px;
  line-height: 1.5;
}

// Divider
.auth-divider {
  display: flex;
  align-items: center;
  margin: 24px 16px 20px;
  gap: 12px;

  &::before,
  &::after {
    content: '';
    flex: 1;
    height: 0.5px;
    background: var(--ylf-separator);
  }
}

.auth-divider-text {
  font-size: 13px;
  color: var(--ion-color-medium, #8e8e93);
  font-weight: 400;
}

// Social Login - Icon circles
.auth-social-icons {
  display: flex;
  justify-content: center;
  gap: 32px;
  padding: 0 16px;
}

.auth-social-circle {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  background: none;
  border: none;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;

  &:active:not(:disabled) {
    opacity: 0.5;
  }

  &:disabled {
    opacity: 0.3;
    cursor: default;
  }
}

.auth-social-circle-icon {
  width: 52px;
  height: 52px;
  padding: 12px;
  border-radius: 50%;
  font-size: 28px;
  background: var(--ylf-fill-secondary);
  color: var(--ion-text-color);

  // 微信 — 品牌绿底白图标
  .auth-social-circle--wechat & {
    background: var(--c-brand-wx);
    color: #fff;
  }
}

// GitHub — 深色底白图标（深色模式反相）
.auth-social-circle--github .auth-social-circle-icon {
  background: #24292f;
  color: #fff;

  .dark & {
    background: #f0f0f0;
    color: #24292f;
  }
}

.auth-social-circle-label {
  font-size: 12px;
  color: var(--ion-color-medium, #8e8e93);
  font-weight: 500;
}

// Footer
.auth-footer {
  padding: 24px 16px 8px;
  text-align: center;
}

.auth-footer-switch {
  font-size: 15px;
  color: var(--ion-color-medium, #8e8e93);
  margin: 0;
}

.auth-link-btn {
  background: none;
  border: none;
  color: var(--ion-color-primary, #007aff);
  font-size: 15px;
  font-weight: 600;
  cursor: pointer;
  padding: 0;
  -webkit-tap-highlight-color: transparent;

  &:active {
    opacity: 0.5;
  }
}

.auth-link {
  color: var(--ion-color-primary, #007aff);
  text-decoration: none;
  font-weight: 500;
}

.auth-terms {
  padding: 20px 16px 16px;
  text-align: center;
}

.auth-terms-text {
  font-size: 12px;
  color: var(--ion-color-medium, #8e8e93);
  line-height: 1.6;
  margin: 0;
}
</style>
