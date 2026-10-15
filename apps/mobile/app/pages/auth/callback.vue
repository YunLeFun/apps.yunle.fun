<script lang="ts" setup>
/**
 * OAuth 回调处理页
 * 处理 GitHub/微信 OAuth 登录回调
 *
 * 两种模式：
 * 1. Web 端：SDK detectSessionInUrl 自动处理 → checkAuthStatus
 * 2. 原生 App（state 以 'app-' 开头）：把 code+state 通过 deeplink 传回 App
 */
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
import { checkmarkCircle, closeCircle } from 'ionicons/icons'
import { useAppsAuthAcquisition } from '~/composables/auth/useAppsAcquisition'
import { NATIVE_OAUTH_STATE_PREFIX } from '~/composables/auth/useCloudbaseOAuth'

const router = useRouter()
const { checkAuthStatus, isAuthenticated, user } = useCloudbaseAuth()
const { recordAfterAuthentication } = useAppsAuthAcquisition(useCloudbaseAuthCore())
// The pre plugin preserves our matching state before SDK cleanup; this is an optional direct echo.
const callbackState = import.meta.client ? new URLSearchParams(window.location.search).get('state') || undefined : undefined
const toast = useToast()

const status = ref<'checking' | 'success' | 'error'>('checking')
const message = ref('正在处理中...')

/**
 * 检测是否来自原生 App 的 OAuth 回调
 * 如果是，通过 deeplink 把 code+state 传回 App
 */
function handleNativeAppCallback(): boolean {
  const params = new URLSearchParams(window.location.search)
  const code = params.get('code')
  const state = params.get('state')

  if (!state?.startsWith(NATIVE_OAUTH_STATE_PREFIX) || !code)
    return false

  // 来自原生 App，通过 deeplink 传回 code+state
  message.value = '正在返回应用...'
  const deeplink = `yunlefun://auth/callback?code=${encodeURIComponent(code)}&state=${encodeURIComponent(state)}`
  window.location.href = deeplink

  // 如果 deeplink 没有立即关闭页面，显示提示
  setTimeout(() => {
    status.value = 'success'
    message.value = '授权成功，请返回云乐坊 App'
  }, 1500)

  return true
}

onMounted(async () => {
  // 先检查是否是原生 App 的回调
  if (handleNativeAppCallback())
    return

  // Web 端正常处理
  try {
    // 等待 CloudBase SDK 的 detectSessionInUrl 自动处理 URL 中的 OAuth 回调参数
    // SDK 会检测 code + state 参数，自动完成 token 交换
    // 给 SDK 足够时间完成初始化和 session 交换
    await new Promise(resolve => setTimeout(resolve, 1000))

    await checkAuthStatus()

    if (isAuthenticated.value && user.value) {
      await recordAfterAuthentication(callbackState)
      status.value = 'success'
      message.value = '登录成功！正在跳转...'
      toast.showSuccess(`欢迎回来，${user.value.nickname || user.value.login}！`)

      setTimeout(() => {
        router.replace('/tabs/me')
      }, 1000)
      return
    }

    // 如果首次检查未成功，可能 SDK 还在处理中，再等一下重试
    await new Promise(resolve => setTimeout(resolve, 1500))
    await checkAuthStatus()

    if (isAuthenticated.value && user.value) {
      await recordAfterAuthentication(callbackState)
      status.value = 'success'
      message.value = '登录成功！正在跳转...'
      toast.showSuccess(`欢迎回来，${user.value.nickname || user.value.login}！`)

      setTimeout(() => {
        router.replace('/tabs/me')
      }, 1000)
      return
    }

    throw new Error('未能获取用户信息，请重试')
  }
  catch (err: unknown) {
    const errMsg = err instanceof Error ? err.message : String(err)
    console.error('OAuth 回调处理失败:', err)
    status.value = 'error'
    message.value = errMsg || '操作失败，请重试'
    toast.showError(errMsg || '登录失败，请重新尝试')

    setTimeout(() => {
      router.push('/login')
    }, 3000)
  }
})
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/login" text="返回" />
        </IonButtons>
        <IonTitle>
          {{ status === 'checking' ? '登录中' : status === 'success' ? '登录成功' : '登录失败' }}
        </IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true" class="ion-padding">
      <div class="callback-container">
        <!-- 状态图标 -->
        <div class="callback-icon">
          <IonSpinner
            v-if="status === 'checking'"
            name="crescent"
            class="callback-spinner"
          />
          <IonIcon
            v-else-if="status === 'success'"
            :icon="checkmarkCircle"
            class="callback-status-icon callback-status-icon--success"
          />
          <IonIcon
            v-else
            :icon="closeCircle"
            class="callback-status-icon callback-status-icon--error"
          />
        </div>

        <!-- 状态文字 -->
        <div class="callback-text">
          <h2 class="callback-title">
            <template v-if="status === 'checking'">
              处理中
            </template>
            <template v-else-if="status === 'success'">
              登录成功
            </template>
            <template v-else>
              登录失败
            </template>
          </h2>
          <p class="callback-message">
            {{ message }}
          </p>
        </div>

        <!-- 失败时显示返回按钮 -->
        <div v-if="status === 'error'" class="callback-actions">
          <k-button
            large
            class="callback-btn"
            @click="router.push('/login')"
          >
            返回登录
          </k-button>
        </div>
      </div>
    </IonContent>
  </IonPage>
</template>

<style lang="scss" scoped>
.callback-container {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  min-height: 60vh;
  text-align: center;
  padding: 0 24px;
}

.callback-icon {
  margin-bottom: 24px;
}

.callback-spinner {
  width: 56px;
  height: 56px;
  color: var(--ion-color-primary, #007aff);
}

.callback-status-icon {
  font-size: 64px;
}

.callback-status-icon--success {
  color: #34c759;
}

.callback-status-icon--error {
  color: #ff3b30;
}

.callback-text {
  margin-bottom: 32px;
}

.callback-title {
  font-size: 24px;
  font-weight: 700;
  color: var(--ion-text-color, #000);
  margin: 0 0 8px;
}

.callback-message {
  font-size: 15px;
  color: var(--ion-color-medium, #8e8e93);
  margin: 0;
  line-height: 1.5;
}

.callback-actions {
  width: 100%;
  max-width: 280px;
}

.callback-btn {
  width: 100%;
}
</style>
