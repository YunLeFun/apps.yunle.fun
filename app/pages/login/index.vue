<script lang="ts" setup>
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
import { alertCircleOutline } from 'ionicons/icons'
import {
  kButton,
} from 'konsta/vue'
import { useWxLoginVerify } from '~/composables/wx'

const router = useRouter()

const userStore = useUserStore()

const { hasCode, errorMessage, loading } = useWxLoginVerify({
  success: (res) => {
    userStore.login(res.access_token, res.user)

    setTimeout(() => {
      router.push('/tabs/me')
    }, 1000)
  },
})
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" text="返回" />
        </IonButtons>
        <IonTitle>登录</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <div class="w-full flex flex-col items-center px-6">
        <Logo mb-8 mt-10 />
        <template v-if="hasCode">
          <div class="flex flex-col items-center justify-center gap-4 text-center">
            <p v-if="loading" class="text-base text-[#8E8E93]">
              {{ loading ? '登录中' : '鉴权中' }}
            </p>
            <IonSpinner v-if="loading" name="crescent" />

            <template v-if="errorMessage">
              <IonIcon :icon="alertCircleOutline" class="text-4xl text-[#FF3B30]" />
              <p class="text-sm text-[#FF3B30]">
                {{ errorMessage }}
              </p>
              <k-button
                large
                class="mt-4 w-full"
                @click="router.push('/tabs/me')"
              >
                返回
              </k-button>
            </template>
          </div>
        </template>
        <UserLogin v-else />
      </div>
    </IonContent>
  </IonPage>
</template>
