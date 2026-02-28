<script lang="ts" setup>
/**
 * OAuth 回调处理页
 * 处理 GitHub/微信 OAuth 登录回调
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

const router = useRouter()
const { checkAuthStatus, isAuthenticated, user } = useCloudbaseAuth()
const toast = useToast()

const status = ref<'checking' | 'success' | 'error'>('checking')
const message = ref('正在处理中...')

onMounted(async () => {
  try {
    // CloudBase SDK detectSessionInUrl: true 会自动处理 URL 中的 OAuth 回调参数
    await new Promise(resolve => setTimeout(resolve, 500))

    await checkAuthStatus()

    if (isAuthenticated.value && user.value) {
      status.value = 'success'
      message.value = '登录成功！正在跳转...'
      toast.showSuccess(`欢迎回来，${user.value.nickname || user.value.login}！`)

      setTimeout(() => {
        router.push('/tabs/me')
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
