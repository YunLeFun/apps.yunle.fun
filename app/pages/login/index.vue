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

watch(isAuthenticated, (value) => {
  if (value) {
    router.push('/tabs/me')
  }
}, { immediate: true })

// 页面模式：登录 / 注册
type PageMode = 'login' | 'signup'
const pageMode = ref<PageMode>('login')

// 登录方式切换
type LoginMode = 'phone' | 'email' | 'password'
const loginMode = ref<LoginMode>('phone')

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
const isPasswordUsername = computed(() => /^[a-z][\w-]{2,19}$/i.test(passwordAccount.value))
const passwordFormValid = computed(() =>
  (isPasswordEmail.value || isPasswordPhone.value || isPasswordUsername.value) && passwordValue.value.length >= 6,
)

// 注册状态
const signupPhone = ref('')
const signupOtpCode = ref('')
const signupData = ref<TcbSignUpData | null>(null)
const signupCodeSent = ref(false)
const { remaining: signupCountdown, isActive: signupCountdownActive, start: startSignupCountdown } = useCountdown()

// 恢复上次密码登录的账号
onMounted(() => {
  const saved = localStorage.getItem(LAST_PASSWORD_ACCOUNT_KEY)
  if (saved)
    passwordAccount.value = saved
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
  }
  catch {}
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
          <Logo class="auth-logo" />
          <h1 class="auth-title">
            {{ pageMode === 'login' ? '登录云乐坊' : '注册云乐坊' }}
          </h1>
          <p class="auth-subtitle">
            {{ pageMode === 'login' ? '使用您的账号继续' : '创建您的云乐坊账号' }}
          </p>
        </div>

        <!-- ===== 登录模式 ===== -->
        <template v-if="pageMode === 'login'">
          <!-- Segmented Control -->
          <div class="auth-segment">
            <button
              class="auth-segment-btn"
              :class="{ active: loginMode === 'phone' }"
              @click="loginMode = 'phone'"
            >
              手机号
            </button>
            <button
              class="auth-segment-btn"
              :class="{ active: loginMode === 'email' }"
              @click="loginMode = 'email'"
            >
              邮箱
            </button>
            <button
              class="auth-segment-btn"
              :class="{ active: loginMode === 'password' }"
              @click="loginMode = 'password'"
            >
              密码
            </button>
          </div>

          <!-- 手机号登录 -->
          <div v-if="loginMode === 'phone'" class="auth-form">
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
          <div v-else-if="loginMode === 'email'" class="auth-form">
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
          <div class="auth-divider">
            <span class="auth-divider-text">其他登录方式</span>
          </div>

          <!-- 第三方登录 - 图标模式 -->
          <div class="auth-social-icons">
            <button class="auth-social-circle" :disabled="loading" @click="loginWithGitHub()">
              <IonIcon :icon="logoGithub" class="auth-social-circle-icon" />
              <span class="auth-social-circle-label">GitHub</span>
            </button>
            <button class="auth-social-circle auth-social-circle--wechat" :disabled="loading" @click="loginWithWeChat()">
              <IonIcon :icon="logoWechat" class="auth-social-circle-icon" />
              <span class="auth-social-circle-label">微信</span>
            </button>
          </div>

          <!-- 注册入口 -->
          <div class="auth-footer">
            <p class="auth-footer-switch">
              还没有账号？
              <button class="auth-link-btn" @click="switchMode('signup')">
                立即注册
              </button>
            </p>
          </div>
        </template>

        <!-- ===== 注册模式 ===== -->
        <template v-else>
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
              <a href="https://www.yunle.fun/docs/terms-of-service" target="_blank" class="auth-link">服务条款</a>
              和
              <a href="https://www.yunle.fun/docs/privacy-policy" target="_blank" class="auth-link">隐私政策</a>
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
            <a href="https://www.yunle.fun/docs/terms-of-service" target="_blank" class="auth-link">服务条款</a>
            和
            <a href="https://www.yunle.fun/docs/privacy-policy" target="_blank" class="auth-link">隐私政策</a>
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
  padding: 20px 0 28px;

  .auth-logo {
    margin-bottom: 12px;
  }

  .auth-title {
    font-size: 28px;
    font-weight: 700;
    color: var(--ion-text-color, #000);
    margin: 0 0 6px;
    letter-spacing: -0.5px;
  }

  .auth-subtitle {
    font-size: 15px;
    color: var(--ion-color-medium, #8e8e93);
    margin: 0;
  }
}

// iOS Segmented Control
.auth-segment {
  display: flex;
  background: var(--ion-color-light, #f2f2f7);
  border-radius: 9px;
  padding: 2px;
  margin: 0 16px 20px;

  .dark & {
    background: #39393d;
  }
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
    background: var(--ion-background-color, #fff);
    box-shadow:
      0 1px 3px rgba(0, 0, 0, 0.04),
      0 3px 8px rgba(0, 0, 0, 0.04);

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

// iOS Grouped Card
.auth-card {
  background: var(--ion-background-color, #fff);
  border-radius: 12px;
  overflow: hidden;
  margin-bottom: 16px;

  .dark & {
    background: var(--ion-card-background, #1c1c1e);
  }
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
  background: var(--ion-color-light, rgba(0, 0, 0, 0.1));
  margin: 0 12px 0 8px;
  flex-shrink: 0;

  .dark & {
    background: rgba(255, 255, 255, 0.15);
  }
}

.auth-card-separator {
  height: 0.5px;
  background: var(--ion-color-light, rgba(0, 0, 0, 0.08));
  margin-left: 16px;

  .dark & {
    background: rgba(255, 255, 255, 0.08);
  }
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
    background: rgba(0, 0, 0, 0.1);

    .dark & {
      background: rgba(255, 255, 255, 0.1);
    }
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
  background: var(--ion-color-light, #f2f2f7);
  color: var(--ion-text-color, #000);

  .dark & {
    background: #2c2c2e;
    color: #fff;
  }

  .auth-social-circle--wechat & {
    color: #07c160;
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
