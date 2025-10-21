<script lang="ts" setup>
import type { WxUserInfo } from '../utils'
import {
  IonBackButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonPage,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'

definePageMeta({
  // layout: 'fullscreen',
})

const route = useRoute()
const router = useRouter()

/**
 * 微信授权状态
 */
const wxAuthState = ref<'' | 'success' | 'error'>('')
const wxUserInfo = ref<WxUserInfo>()

const errorInfo = ref('')

const { $api } = useNuxtApp()

onMounted(async () => {
  const { code, state } = route.query
  if (code && state) {
    // 授权重定向成功

    // 1. 通过服务端代理发送 code 获取用户信息（更安全）
    const res = await $api<{
      success: boolean
      msg: string
      data: WxUserInfo
    }>('/wx/auth', {
      method: 'GET',
      query: {
        code,
      },
    })

    if (res.success) {
      wxAuthState.value = 'success'
      wxUserInfo.value = res.data

      // 微信登录成功后重定向到我的页面
      setTimeout(() => {
        router.push('/tabs/profile')
      }, 1000)
    }
    else {
      wxAuthState.value = 'error'
      // consola.error(res.msg)
      errorInfo.value = res.msg
    }
  }
})
</script>

<template>
  <IonPage>
    <IonHeader>
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/profile" />
        </IonButtons>
        <IonTitle>登录</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent class="ion-padding">
      <div class="w-full items-center" flex="~ col">
        <Logo mb-8 mt-10 />
        <UserLogin />

        <br>
        <WxUserInfo
          v-if="wxAuthState === 'success'"
          :user-info="wxUserInfo"
        />
        <div v-if="wxAuthState === 'error'" class="text-red-500">
          授权失败: {{ errorInfo }}
        </div>
      </div>
    </IonContent>
  </IonPage>
</template>
