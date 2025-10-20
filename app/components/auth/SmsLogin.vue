<script lang="ts" setup>
import { IonButton, IonIcon, IonInput, IonItem, IonLabel, IonNote } from '@ionic/vue'
import { keyOutline, phonePortraitOutline } from 'ionicons/icons'
import { useSmsAuth } from '~/composables/auth/useSmsAuth'

const emit = defineEmits<{
  success: [user: any]
}>()

const router = useRouter()

const {
  phoneNumber,
  verifyCode,
  sendingCode,
  processing: loggingIn,
  countdown,
  sendVerifyCode,
  loginWithSms,
} = useSmsAuth()

const errorMessage = ref('')

async function handleSendCode() {
  errorMessage.value = ''

  const result = await sendVerifyCode()
  if (result.success) {
    await showIonicToast('验证码已发送，请查收短信')
  }
  else {
    errorMessage.value = result.message
  }
}

async function handleLogin() {
  errorMessage.value = ''

  const result = await loginWithSms()
  if (result.success) {
    await showIonicToast('登录成功')
    emit('success', result.user)

    // 登录成功后重定向到用户信息页面
    setTimeout(() => {
      router.push('/user')
    }, 500)
  }
  else {
    errorMessage.value = result.message
  }
}
</script>

<template>
  <div class="w-full space-y-4">
    <!-- 手机号输入 -->
    <IonItem lines="none" class="rounded-lg">
      <template #start>
        <IonIcon :icon="phonePortraitOutline" />
      </template>
      <IonLabel position="stacked">
        手机号
      </IonLabel>
      <div class="w-full flex items-center">
        <span class="mr-2 text-gray-500">+86</span>
        <IonInput
          v-model="phoneNumber"
          type="tel"
          placeholder="请输入手机号"
          :maxlength="11"
          class="flex-1"
          @keyup.enter="handleSendCode"
        />
      </div>
    </IonItem>

    <IonButton
      expand="block"
      fill="outline"
      size="small"
      :disabled="sendingCode || countdown > 0"
      @click="handleSendCode"
    >
      <span v-if="countdown > 0">{{ countdown }}s 后重新获取</span>
      <span v-else-if="sendingCode">发送中...</span>
      <span v-else>获取验证码</span>
    </IonButton>

    <!-- 验证码输入 -->
    <div class="space-y-2">
      <IonItem lines="none" class="rounded-lg">
        <template #start>
          <IonIcon :icon="keyOutline" />
        </template>
        <IonLabel position="stacked">
          验证码
        </IonLabel>
        <IonInput
          v-model="verifyCode"
          type="text"
          placeholder="请输入验证码"
          :maxlength="6"
          @keyup.enter="handleLogin"
        />
      </IonItem>
    </div>

    <!-- 错误消息 -->
    <IonNote v-if="errorMessage" color="danger" class="block text-center">
      {{ errorMessage }}
    </IonNote>

    <!-- 登录按钮 -->
    <IonButton
      expand="block"
      color="primary"
      :disabled="loggingIn || !phoneNumber || !verifyCode"
      @click="handleLogin"
    >
      {{ loggingIn ? '登录中...' : '登录' }}
    </IonButton>
  </div>
</template>
