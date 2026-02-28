<script setup lang="ts">
import type { YlfUserInfo } from '~~/packages/auth/src'
import {
  calendarOutline,
  femaleOutline,
  helpCircleOutline,
  idCardOutline,
  locationOutline,
  logOut,
  maleOutline,
  person,
  settingsOutline,
  shieldCheckmarkOutline,
} from 'ionicons/icons'
import {
  kBlock,
  kBlockTitle,
  kButton,
  kList,
  kListItem,
} from 'konsta/vue'

const router = useRouter()
const userStore = useUserStore()
const { confirmLogout, isLoggingOut } = useLogout()

const { $api } = useNuxtApp()
const fullUserInfo = ref<YlfUserInfo | null>(null)
const isLoading = ref(false)

async function loadUserInfo() {
  try {
    isLoading.value = true
    const data = await $api<YlfUserInfo>('/auth/profile')
    fullUserInfo.value = data
  }
  catch (error) {
    console.error('加载用户信息失败:', error)
  }
  finally {
    isLoading.value = false
  }
}

await loadUserInfo()

const selectedGender = ref<0 | 1 | 2>(fullUserInfo.value?.profile?.sex ?? 0)
const isEditingGender = ref(false)

const genderIcon = computed(() => {
  const sex = fullUserInfo.value?.profile?.sex
  if (!sex)
    return helpCircleOutline
  return sex === 1 ? maleOutline : femaleOutline
})

const genderText = computed(() => {
  const sex = fullUserInfo.value?.profile?.sex
  if (!sex)
    return '保密'
  return sex === 1 ? '男' : '女'
})

const locationText = computed(() => {
  if (!fullUserInfo.value?.profile)
    return '未知'
  const { country, province, city } = fullUserInfo.value.profile
  const parts = [country, province, city].filter(Boolean)
  return parts.length > 0 ? parts.join(' ') : '未知'
})

const hasPrivileges = computed(() => {
  return fullUserInfo.value?.profile?.privilege && fullUserInfo.value.profile.privilege.length > 0
})

function handleLogout() {
  confirmLogout()
}

async function handleRefresh() {
  await loadUserInfo()
}

function openGenderSelect() {
  selectedGender.value = fullUserInfo.value?.profile?.sex ?? 0
  isEditingGender.value = true
}

async function handleGenderChange() {
  try {
    if (fullUserInfo.value?.profile) {
      fullUserInfo.value.profile.sex = selectedGender.value
    }
    isEditingGender.value = false
  }
  catch (error) {
    console.error('更新性别失败:', error)
  }
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" text="我" />
        </IonButtons>
        <IonTitle>个人资料</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <!-- 未登录状态 -->
      <div v-if="!userStore.isLoggedIn" class="h-full flex flex-col items-center justify-center px-8">
        <IonIcon :icon="person" class="mb-4 text-6xl" color="medium" />
        <p class="mb-6 text-base ios-secondary-text">
          请先登录查看个人资料
        </p>
        <k-button
          large
          class="w-full"
          @click="router.push('/login')"
        >
          去登录
        </k-button>
      </div>

      <!-- 已登录状态 -->
      <template v-else>
        <!-- 头像和基本信息 -->
        <k-block strong inset class="mt-4">
          <div class="flex flex-col items-center py-4 text-center">
            <div class="mb-4 h-24 w-24 overflow-hidden rounded-full">
              <img
                v-if="userInfo.avatar || fullUserInfo?.profile?.headimgurl"
                :src="(userInfo.avatar || fullUserInfo?.profile?.headimgurl)!"
                :alt="userInfo.nickname || fullUserInfo?.profile?.nickname"
                class="h-full w-full object-cover"
              >
              <div
                v-else
                class="h-full w-full flex items-center justify-center ios-avatar-bg"
              >
                <IonIcon :icon="person" class="text-4xl text-white" />
              </div>
            </div>

            <h2 class="mb-1 text-xl font-bold">
              {{ userInfo.nickname || fullUserInfo?.nickname || '无名氏' }}
            </h2>

            <button class="mt-1 flex cursor-pointer items-center gap-1 border-none bg-transparent ios-secondary-text" @click="openGenderSelect">
              <IonIcon :icon="genderIcon" class="text-base" />
              <span class="text-sm">{{ genderText }}</span>
            </button>
          </div>
        </k-block>

        <!-- 详细信息 -->
        <k-block-title>详细信息</k-block-title>
        <k-list strong inset>
          <k-list-item
            title="地理位置"
            :after="locationText"
          >
            <template #media>
              <span class="ios-icon-box ios-icon-blue">
                <IonIcon :icon="locationOutline" />
              </span>
            </template>
          </k-list-item>

          <k-list-item
            v-if="fullUserInfo?.profile?.openid"
            title="用户标识"
            :subtitle="fullUserInfo.profile.openid"
          >
            <template #media>
              <span class="ios-icon-box ios-icon-orange">
                <IonIcon :icon="idCardOutline" />
              </span>
            </template>
          </k-list-item>

          <k-list-item
            v-if="fullUserInfo?.profile?.unionid"
            title="统一标识"
            :subtitle="fullUserInfo.profile.unionid"
          >
            <template #media>
              <span class="ios-icon-box ios-icon-green">
                <IonIcon :icon="shieldCheckmarkOutline" />
              </span>
            </template>
          </k-list-item>
        </k-list>

        <!-- 特权信息 -->
        <template v-if="hasPrivileges">
          <k-block-title>特权信息</k-block-title>
          <k-block strong inset>
            <div class="flex flex-wrap gap-2">
              <span
                v-for="privilege in fullUserInfo?.profile?.privilege"
                :key="privilege"
                class="ios-badge"
              >
                {{ privilege }}
              </span>
            </div>
          </k-block>
        </template>

        <!-- 账户统计 -->
        <k-block-title>账户统计</k-block-title>
        <k-block strong inset>
          <div class="flex">
            <div class="flex-1 text-center">
              <div class="text-xl font-bold ios-primary-text">
                {{ userStore.accessToken ? '已认证' : '未认证' }}
              </div>
              <div class="mt-1 text-xs ios-secondary-text">
                认证状态
              </div>
            </div>
            <div class="flex-1 text-center">
              <div class="text-xl font-bold ios-primary-text">
                {{ new Date().toLocaleDateString() }}
              </div>
              <div class="mt-1 text-xs ios-secondary-text">
                最后登录
              </div>
            </div>
          </div>
        </k-block>

        <!-- 操作 -->
        <k-block-title>操作</k-block-title>
        <k-list strong inset>
          <k-list-item
            link
            title="刷新信息"
            @click="handleRefresh"
          >
            <template #media>
              <span class="ios-icon-box ios-icon-blue">
                <IonIcon :icon="calendarOutline" />
              </span>
            </template>
          </k-list-item>

          <k-list-item
            link
            title="设置"
            @click="router.push('/user/settings')"
          >
            <template #media>
              <span class="ios-icon-box ios-icon-gray">
                <IonIcon :icon="settingsOutline" />
              </span>
            </template>
          </k-list-item>
        </k-list>

        <k-list strong inset class="mt-8">
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
      </template>

      <!-- 性别选择 Modal -->
      <IonModal :is-open="isEditingGender" @did-dismiss="isEditingGender = false">
        <IonHeader>
          <IonToolbar>
            <IonTitle>选择性别</IonTitle>
            <IonButtons slot="end">
              <IonButton @click="isEditingGender = false">
                取消
              </IonButton>
            </IonButtons>
          </IonToolbar>
        </IonHeader>
        <IonContent>
          <k-list strong inset class="mt-4">
            <k-list-item
              title="男"
              :after="selectedGender === 1 ? '✓' : ''"
              @click="selectedGender = 1; handleGenderChange()"
            >
              <template #media>
                <span class="ios-icon-box ios-icon-blue">
                  <IonIcon :icon="maleOutline" />
                </span>
              </template>
            </k-list-item>
            <k-list-item
              title="女"
              :after="selectedGender === 2 ? '✓' : ''"
              @click="selectedGender = 2; handleGenderChange()"
            >
              <template #media>
                <span class="ios-icon-box ios-icon-orange">
                  <IonIcon :icon="femaleOutline" />
                </span>
              </template>
            </k-list-item>
            <k-list-item
              title="保密"
              :after="selectedGender === 0 ? '✓' : ''"
              @click="selectedGender = 0; handleGenderChange()"
            >
              <template #media>
                <span class="ios-icon-box ios-icon-gray">
                  <IonIcon :icon="helpCircleOutline" />
                </span>
              </template>
            </k-list-item>
          </k-list>
        </IonContent>
      </IonModal>
    </IonContent>
  </IonPage>
</template>

