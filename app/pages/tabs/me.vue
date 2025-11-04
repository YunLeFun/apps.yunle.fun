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
import { informationCircle, logIn, logOut, person, personCircle, personCircleOutline, settings } from 'ionicons/icons'

const router = useRouter()

const userStore = useUserStore()

const { confirmLogout, isLoggingOut } = useLogout()

function handleLogout() {
  confirmLogout()
}

function goToLoginPage() {
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

      <IonList v-if="!userStore.isLoggedIn" inset>
        <IonItem @click="goToLoginPage">
          <IonIcon
            slot="start"
            color="primary"
            :icon="personCircleOutline"
            class="text-6xl"
          />
          <IonLabel color="primary">
            登录「云乐坊」账户
          </IonLabel>
        </IonItem>
      </IonList>
      <IonList v-else inset class="py-2">
        <IonItem @click="goToLoginPage">
          <IonAvatar slot="start">
            <img
              v-if="userInfo.avatar"
              :src="userInfo.avatar"
              :alt="userInfo.nickname"
            >
          </IonAvatar>
          <IonLabel>
            {{ userInfo.nickname }}
          </IonLabel>
        </IonItem>
      </IonList>

      <!-- 功能列表 -->
      <IonList v-if="userStore.isLoggedIn" inset>
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
