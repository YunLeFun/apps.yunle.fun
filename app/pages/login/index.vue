<script lang="ts" setup>
import type { WxUserInfo } from '../../utils'
import {
  IonBackButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonPage,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { consola } from 'consola'
import { useRoute } from 'vue-router'

const route = useRoute()
const router = useRouter()

const userStore = useUserStore()

/**
 * 有 code 登录鉴权中
 */
const hasCode = computed(() => !!route.query.code)

const loading = ref(false)

onMounted(async () => {
  if (hasCode.value) {
    loading.value = true

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
      }
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
          <div class="flex flex-col items-center justify-center gap-2 text-center font-bold">
            <span>
              {{ loading ? '登录中' : '鉴权中' }}
            </span>
            <ion-spinner />
          </div>
        </template>
        <UserLogin v-else />
      </div>
    </IonContent>
  </IonPage>
</template>
