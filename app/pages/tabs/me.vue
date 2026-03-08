<script setup lang="ts">
import {
  IonContent,
  IonHeader,
  IonPage,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { apps, chatbubbleEllipsesOutline, codeSlashOutline, helpCircleOutline, informationCircle, personCircleOutline, settings, swapHorizontalOutline } from 'ionicons/icons'
import {
  kList,
  kListItem,
} from 'konsta/vue'

const router = useRouter()

const userStore = useUserStore()
const developerStore = useDeveloperStore()
const accountsStore = useAccountsStore()

const otherAccounts = computed(() =>
  accountsStore.getOtherAccounts(userStore.userInfo?.id),
)

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
          footer="登录以使用全部功能"
          inner-class="k-list-item-vcenter"
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
          footer="查看个人资料"
          inner-class="k-list-item-vcenter"
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

      <!-- 我的应用（登录后可见） -->
      <k-list v-if="userStore.isLoggedIn" strong inset>
        <k-list-item
          link
          title="我的应用"
          subtitle="创建和管理你的应用"
          inner-class="k-list-item-vcenter"
          @click="navigateTo('/apps/my')"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-blue">
              <IonIcon :icon="apps" />
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
      </k-list>

      <!-- 帮助 & 反馈 & 关于 -->
      <k-list strong inset>
        <k-list-item
          link
          title="帮助"
          @click="navigateTo('/help')"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-blue">
              <IonIcon :icon="helpCircleOutline" />
            </span>
          </template>
        </k-list-item>

        <k-list-item
          link
          title="反馈"
          @click="navigateTo('/feedback')"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-orange">
              <IonIcon :icon="chatbubbleEllipsesOutline" />
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

      <!-- 开发者模式（仅开启后可见） -->
      <k-list v-if="developerStore.enabled" strong inset>
        <k-list-item
          link
          title="开发者选项"
          @click="navigateTo('/developer')"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-purple">
              <IonIcon :icon="codeSlashOutline" />
            </span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 切换账号 / 退出登录 -->
      <k-list v-if="userStore.isLoggedIn" strong inset class="mt-8">
        <k-list-item
          link
          title="切换 / 退出账号"
          :footer="otherAccounts.length > 0 ? `还有 ${otherAccounts.length} 个已保存的账号` : '管理已登录的账号'"
          @click="navigateTo('/accounts')"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-blue">
              <IonIcon :icon="swapHorizontalOutline" />
            </span>
          </template>
        </k-list-item>
      </k-list>
    </IonContent>
  </IonPage>
</template>
