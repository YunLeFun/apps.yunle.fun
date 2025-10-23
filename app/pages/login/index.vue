<script lang="ts" setup>
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
import { alertCircleOutline } from 'ionicons/icons'
import { useWxLoginVerify } from '~/composables/wx'

const router = useRouter()

const userStore = useUserStore()

const { hasCode, errorMessage, loading } = useWxLoginVerify({
  success: (res) => {
    // 保存 JWT access_token 和用户信息到 userStore
    userStore.login(res.access_token, res.user)

    // 微信登录成功后重定向到我的页面
    setTimeout(() => {
      router.push('/tabs/me')
    }, 1000)
  },
})
</script>

<template>
  <IonPage>
    <IonHeader>
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" />
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
                @click="router.push('/tabs/me')"
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
