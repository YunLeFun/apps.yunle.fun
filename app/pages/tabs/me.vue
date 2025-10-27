<script setup lang="ts">
import {
  IonAvatar,
  IonButton,
  IonCard,
  IonCardContent,
  IonCardHeader,
  IonCardTitle,
  IonContent,
  IonHeader,
  IonIcon,
  IonItem,
  IonLabel,
  IonList,
  IonPage,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { informationCircle, logIn, logOut, person, settings } from 'ionicons/icons'

const router = useRouter()

const userStore = useUserStore()

const { confirmLogout, isLoggingOut } = useLogout()

function handleLogout() {
  confirmLogout()
}

function goToLogin() {
  router.push('/login')
}
</script>

<template>
  <IonPage>
    <IonHeader>
      <IonToolbar>
        <IonTitle>我的</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent class="ion-padding">
      <!-- 用户信息卡片 -->
      <IonCard>
        <IonCardHeader>
          <div class="flex items-center gap-4">
            <IonAvatar>
              <img
                v-if="userInfo.avatar"
                :src="userInfo.avatar"
                :alt="userInfo.nickname"
              >
              <IonIcon
                v-else
                :icon="person"
                class="text-4xl"
              />
            </IonAvatar>
            <div class="flex-1">
              <IonCardTitle>{{ userInfo.nickname }}</IonCardTitle>
            </div>
          </div>
        </IonCardHeader>

        <IonCardContent v-if="!userStore.isLoggedIn">
          <IonButton
            expand="block"
            @click="goToLogin"
          >
            <IonIcon slot="start" :icon="logIn" />
            登录
          </IonButton>
        </IonCardContent>
      </IonCard>

      <!-- 功能列表 -->
      <IonList v-if="userStore.isLoggedIn" inset class="mt-4">
        <IonItem button router-link="/user/profile">
          <IonIcon slot="start" :icon="person" />
          <IonLabel>个人资料</IonLabel>
        </IonItem>

        <IonItem button router-link="/user/settings">
          <IonIcon slot="start" :icon="settings" />
          <IonLabel>设置</IonLabel>
        </IonItem>

        <IonItem
          button
          :disabled="isLoggingOut"
          @click="handleLogout"
        >
          <IonIcon slot="start" :icon="logOut" />
          <IonLabel>{{ isLoggingOut ? '退出中...' : '退出登录' }}</IonLabel>
        </IonItem>
      </IonList>

      <IonList inset>
        <IonItem button router-link="/user/settings">
          <IonIcon slot="start" :icon="settings" />
          <IonLabel>设置</IonLabel>
        </IonItem>

        <IonItem button router-link="/about">
          <IonIcon slot="start" :icon="informationCircle" />
          <IonLabel>关于</IonLabel>
        </IonItem>
      </IonList>
    </IonContent>
  </IonPage>
</template>
