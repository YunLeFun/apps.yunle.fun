<script setup lang="ts">
import {
  IonContent,
  IonHeader,
  IonPage,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { informationCircle, logOut, person, personCircleOutline, settings } from 'ionicons/icons'
import {
  kList,
  kListItem,
} from 'konsta/vue'

const router = useRouter()

const userStore = useUserStore()

const { confirmLogout, isLoggingOut } = useLogout()

function handleLogout() {
  confirmLogout()
}

function goToLoginPage() {
  router.push('/login')
}

function navigateTo(path: string) {
  router.push(path)
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonTitle>我的</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <IonHeader collapse="condense">
        <IonToolbar>
          <IonTitle size="large">
            我的
          </IonTitle>
        </IonToolbar>
      </IonHeader>

      <!-- 未登录：登录入口（iOS Settings Apple ID 风格） -->
      <k-list v-if="!userStore.isLoggedIn" strong inset class="mt-1">
        <k-list-item
          link
          title="登录「云乐坊」账户"
          subtitle="登录以使用全部功能"
          class="ios-login-entry"
          @click="goToLoginPage"
        >
          <template #media>
            <IonIcon
              :icon="personCircleOutline"
              class="text-5xl opacity-40"
              color="medium"
            />
          </template>
        </k-list-item>
      </k-list>

      <!-- 已登录：用户信息 -->
      <k-list v-else strong inset class="mt-1">
        <k-list-item
          link
          :title="userInfo.nickname || '云乐坊用户'"
          subtitle="查看个人资料"
          @click="navigateTo('/user/profile')"
        >
          <template #media>
            <img
              v-if="userInfo.avatar"
              :src="userInfo.avatar"
              :alt="userInfo.nickname"
              class="h-14 w-14 rounded-full object-cover"
            >
            <div
              v-else
              class="ios-icon-avatar"
            >
              <span class="text-xl text-white font-semibold">
                {{ (userInfo.nickname || '云')[0] }}
              </span>
            </div>
          </template>
        </k-list-item>
      </k-list>

      <!-- 功能列表 -->
      <k-list v-if="userStore.isLoggedIn" strong inset>
        <k-list-item
          link
          title="个人资料"
          @click="navigateTo('/user/profile')"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-blue">
              <IonIcon :icon="person" />
            </span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 通用功能 -->
      <k-list strong inset>
        <k-list-item
          link
          title="设置"
          @click="navigateTo('/user/settings')"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-gray">
              <IonIcon :icon="settings" />
            </span>
          </template>
        </k-list-item>

        <k-list-item
          link
          title="关于"
          @click="navigateTo('/about')"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-blue">
              <IonIcon :icon="informationCircle" />
            </span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 退出登录 -->
      <k-list v-if="userStore.isLoggedIn" strong inset class="mt-8">
        <k-list-item
          link
          :title="isLoggingOut ? '退出中...' : '退出登录'"
          class="k-list-item-destructive"
          @click="handleLogout"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-red">
              <IonIcon :icon="logOut" />
            </span>
          </template>
        </k-list-item>
      </k-list>
    </IonContent>
  </IonPage>
</template>

