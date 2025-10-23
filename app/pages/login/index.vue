<script lang="ts" setup>
import type { WxUserInfo } from '../../utils'
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonPage,
  IonSpinner,
  IonText,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { consola } from 'consola'
import { alertCircleOutline } from 'ionicons/icons'
import { useRoute } from 'vue-router'

const route = useRoute()
const router = useRouter()

const userStore = useUserStore()

/**
 * 有 code 登录鉴权中
 */
const hasCode = computed(() => !!route.query.code)

const loading = ref(false)
const errorMessage = ref('')

onMounted(async () => {
  if (hasCode.value) {
    const code = route.query.code
    const state = route.query.state

    loading.value = true
    errorMessage.value = ''

    // jwt 授权重定向成功
    try {
      const res = await $fetch<{
        access_token: string
        user: {
          id: string
          nickname: string
          avatar: string
          profile: WxUserInfo
        }
      }>('https://api.yunle.fun/auth/wechat/callback', {
        method: 'GET',
        query: {
          code,
          state,
        },
      })

      if (res.access_token) {
      // 保存用户信息
        userStore.setUserInfo(res.user)

        // 微信登录成功后重定向到我的页面
        setTimeout(() => {
          router.push('/tabs/profile')
        }, 1000)
      }
      else {
        consola.error(res)
        errorMessage.value = '登录失败，请重试'
      }
    }
    catch (error) {
      consola.error('登录失败:', error)
      errorMessage.value = '登录失败，请检查网络连接后重试'
    }
    finally {
      loading.value = false
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
        <template v-if="hasCode">
          <div class="flex flex-col items-center justify-center gap-4 text-center">
            <IonText v-if="loading" color="medium">
              <h3>{{ loading ? '登录中' : '鉴权中' }}</h3>
            </IonText>
            <IonSpinner v-if="loading" name="crescent" />

            <template v-if="errorMessage">
              <IonIcon :icon="alertCircleOutline" color="danger" size="large" />
              <IonText color="danger">
                <p class="ion-text-wrap">
                  {{ errorMessage }}
                </p>
              </IonText>
              <IonButton
                expand="block"
                color="primary"
                @click="router.push('/tabs/profile')"
              >
                返回
              </IonButton>
            </template>
          </div>
        </template>
        <UserLogin v-else />
      </div>
    </IonContent>
  </IonPage>
</template>
