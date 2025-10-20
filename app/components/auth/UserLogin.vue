<script lang="ts" setup>
import type { YlfAppInfo } from '~~/packages/types'
import { IonButton, IonCard, IonCardContent, IonIcon, IonLabel, IonSegment, IonSegmentButton } from '@ionic/vue'
import { consola } from 'consola'
import { logoWechat } from 'ionicons/icons'
import { useUserLogin } from '../../composables/useUserLogin'

const userLogin = useUserLogin()
const router = useRouter()

const appInfo = ref<YlfAppInfo>()

const route = useRoute()

// 登录方式切换
const loginMethod = ref<'wechat' | 'sms'>('sms')

function handleSmsLoginSuccess(user: any) {
  consola.log('短信登录成功:', user)
  // 登录成功后重定向到用户信息页面
  setTimeout(() => {
    router.push('/user')
  }, 500)
}

onMounted(() => {
  $fetch('/api/app/search', {
    method: 'GET',
    query: {
      id: route.query.appId,
    },
  }).then((res) => {
    if ('data' in res) {
      appInfo.value = res.data
    }
  })
})
</script>

<template>
  <DarkToggle class="absolute right-4 top-4" />

  <div
    class="w-full flex items-center justify-center"
    m="auto"
    max-w-md
  >
    <IonCard class="w-full">
      <IonCardContent class="p-6">
        <LoginForApp v-if="appInfo" :app-info="appInfo" />

        <!-- 登录方式切换 -->
        <IonSegment
          v-model="loginMethod"
          class="mb-6"
        >
          <IonSegmentButton value="sms">
            <IonLabel>短信登录</IonLabel>
          </IonSegmentButton>
          <IonSegmentButton value="wechat">
            <IonLabel>微信登录</IonLabel>
          </IonSegmentButton>
        </IonSegment>

        <!-- 短信登录 -->
        <SmsLogin
          v-if="loginMethod === 'sms'"
          @success="handleSmsLoginSuccess"
        />

        <!-- 微信登录 -->
        <div v-else-if="loginMethod === 'wechat'" class="flex flex-col items-center gap-4">
          <IonButton
            expand="block"
            color="success"
            class="w-full"
            :disabled="userLogin.wxLoginLoading.value"
            @click="userLogin.loginByWechat"
          >
            <template #start>
              <IonIcon :icon="logoWechat" />
            </template>
            {{ userLogin.wxLoginLoading.value ? '登录中...' : '微信登录' }}
          </IonButton>
        </div>
      </IonCardContent>
    </IonCard>
  </div>
</template>
