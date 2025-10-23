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

definePageMeta({
  // layout: 'fullscreen',
})

const route = useRoute()
const router = useRouter()

const userStore = useUserStore()

onMounted(async () => {
  const { code } = route.query
  if (code) {
    // jwt 授权重定向成功
    const res = await $fetch<{
      access_token: string
      user: {
        id: string
        nickname: string
        avatar: string
        profile: WxUserInfo
      }
    }>('/auth/wechat/callback', {
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
      </div>
    </IonContent>
  </IonPage>
</template>
