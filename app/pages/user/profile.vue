<script setup lang="ts">
import { IonPage } from '@ionic/vue'
import {
  callOutline,
  checkmarkCircle,
  closeCircle,
  copyOutline,
  keyOutline,
  logoGithub,
  logOut,
  logoWechat,
  mailOutline,
  personOutline,
  qrCodeOutline,
  refreshOutline,
  textOutline,
  timeOutline,
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

const {
  user,
  authLoading,
  displayName,
  displayDescription,
  displayPhone,
  displayEmail,
  displayGender,
  joinDate,
  avatarInitial,
  isGitHubBound,
  isWeChatBound,
  isPhoneBound,
  isEmailBound,
  hasPassword,
  fetchUser,
  editNickname,
  editGender,
  handlePhoneTap,
  handleWeChatTap,
  handleGitHubTap,
  copyToClipboard,
  handleRefresh,
  updateUserInfo,
} = useProfileEdit()

await fetchUser()

// === Modal 状态 ===
const pageRef = ref<InstanceType<typeof IonPage>>()
const isDescModalOpen = ref(false)
const isEmailModalOpen = ref(false)
const isPasswordModalOpen = ref(false)
const isQrcodeModalOpen = ref(false)

async function handleDescSave(val: string) {
  if (val === (user.value?.description || '')) {
    isDescModalOpen.value = false
    return
  }
  const success = await updateUserInfo({ description: val } as any)
  if (success)
    isDescModalOpen.value = false
}
</script>

<template>
  <IonPage ref="pageRef">
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" text="我" />
        </IonButtons>
        <IonTitle>个人资料</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <!-- 未登录 -->
      <div v-if="!userStore.isLoggedIn" class="h-full flex flex-col items-center justify-center px-8">
        <IonIcon :icon="personOutline" class="mb-4 text-6xl" color="medium" />
        <p class="mb-6 text-base ios-secondary-text">
          请先登录查看个人资料
        </p>
        <k-button large class="w-full" @click="router.push('/login')">
          去登录
        </k-button>
      </div>

      <!-- 已登录 -->
      <template v-else>
        <!-- 用户卡片 -->
        <k-block strong inset class="mt-4">
          <div class="flex items-center gap-4 py-2">
            <div class="h-18 w-18 shrink-0 overflow-hidden rounded-full">
              <UserAvatar
                :src="(userInfo.avatar || user?.avatar)!"
                :alt="displayName"
                telemetry-surface="user.profile"
                class="h-full w-full object-cover"
              >
                <template #fallback>
                  <div class="h-full w-full flex items-center justify-center ios-avatar-bg">
                    <span class="text-2xl font-semibold text-white">{{ avatarInitial }}</span>
                  </div>
                </template>
              </UserAvatar>
            </div>
            <div class="min-w-0 flex-1">
              <h2 class="text-xl font-bold truncate">
                {{ displayName }}
              </h2>
              <p v-if="displayDescription" class="mt-0.5 text-sm ios-secondary-text line-clamp-2">
                {{ displayDescription }}
              </p>
              <p v-if="user?.email" class="mt-0.5 text-sm ios-secondary-text truncate">
                {{ user.email }}
              </p>
            </div>
            <button
              class="shrink-0 flex items-center justify-center rounded-full p-2 active:bg-gray-100 dark:active:bg-zinc-700"
              @click="isQrcodeModalOpen = true"
            >
              <IonIcon :icon="qrCodeOutline" class="text-2xl ios-secondary-text" />
            </button>
          </div>
        </k-block>

        <!-- 基本信息 -->
        <k-block-title>基本信息</k-block-title>
        <k-list strong inset>
          <k-list-item title="昵称" :after="displayName" link @click="editNickname">
            <template #media>
              <span class="ios-icon-box ios-icon-blue"><IonIcon :icon="personOutline" /></span>
            </template>
          </k-list-item>

          <k-list-item title="个人简介" link @click="isDescModalOpen = true">
            <template #media>
              <span class="ios-icon-box ios-icon-purple"><IonIcon :icon="textOutline" /></span>
            </template>
            <template #after>
              <span class="text-sm max-w-48 truncate">{{ displayDescription || '未设置' }}</span>
            </template>
          </k-list-item>

          <k-list-item title="性别" :after="displayGender" link @click="editGender">
            <template #media>
              <span class="ios-icon-box ios-icon-pink"><IonIcon :icon="personOutline" /></span>
            </template>
          </k-list-item>

          <k-list-item title="手机号" link @click="handlePhoneTap">
            <template #media>
              <span class="ios-icon-box ios-icon-green"><IonIcon :icon="callOutline" /></span>
            </template>
            <template #after>
              <div class="flex items-center gap-1.5">
                <span class="text-sm">{{ displayPhone }}</span>
                <IonIcon
                  :icon="isPhoneBound ? checkmarkCircle : closeCircle"
                  :class="isPhoneBound ? 'text-green-500' : 'text-gray-400'"
                  class="text-base"
                />
              </div>
            </template>
          </k-list-item>

          <k-list-item title="邮箱" link @click="isEmailModalOpen = true">
            <template #media>
              <span class="ios-icon-box ios-icon-blue"><IonIcon :icon="mailOutline" /></span>
            </template>
            <template #after>
              <div class="flex items-center gap-1.5">
                <span class="text-sm">{{ displayEmail }}</span>
                <IonIcon
                  :icon="isEmailBound ? checkmarkCircle : closeCircle"
                  :class="isEmailBound ? 'text-green-500' : 'text-gray-400'"
                  class="text-base"
                />
              </div>
            </template>
          </k-list-item>

          <k-list-item title="注册时间" :after="joinDate">
            <template #media>
              <span class="ios-icon-box ios-icon-orange"><IonIcon :icon="timeOutline" /></span>
            </template>
          </k-list-item>
        </k-list>

        <!-- 绑定账号 -->
        <k-block-title>绑定账号</k-block-title>
        <k-list strong inset>
          <k-list-item title="GitHub" link @click="handleGitHubTap">
            <template #media>
              <span class="ios-icon-box ios-icon-gray"><IonIcon :icon="logoGithub" /></span>
            </template>
            <template #after>
              <div class="flex items-center gap-1.5">
                <span class="text-sm">{{ isGitHubBound ? '已绑定' : '未绑定' }}</span>
                <IonIcon
                  :icon="isGitHubBound ? checkmarkCircle : closeCircle"
                  :class="isGitHubBound ? 'text-green-500' : 'text-gray-400'"
                  class="text-base"
                />
              </div>
            </template>
          </k-list-item>

          <k-list-item title="微信" link @click="handleWeChatTap">
            <template #media>
              <span class="ios-icon-box ios-icon-green"><IonIcon :icon="logoWechat" /></span>
            </template>
            <template #after>
              <div class="flex items-center gap-1.5">
                <span class="text-sm">{{ isWeChatBound ? '已绑定' : '未绑定' }}</span>
                <IonIcon
                  :icon="isWeChatBound ? checkmarkCircle : closeCircle"
                  :class="isWeChatBound ? 'text-green-500' : 'text-gray-400'"
                  class="text-base"
                />
              </div>
            </template>
          </k-list-item>
        </k-list>

        <!-- 安全 -->
        <k-block-title>安全</k-block-title>
        <k-list strong inset>
          <k-list-item title="登录密码" :link="hasPassword" @click="hasPassword && (isPasswordModalOpen = true)">
            <template #media>
              <span class="ios-icon-box ios-icon-orange"><IonIcon :icon="keyOutline" /></span>
            </template>
            <template #after>
              <div class="flex items-center gap-1.5">
                <span class="text-sm">{{ hasPassword ? '已设置' : '未设置' }}</span>
                <IonIcon
                  :icon="hasPassword ? checkmarkCircle : closeCircle"
                  :class="hasPassword ? 'text-green-500' : 'text-gray-400'"
                  class="text-base"
                />
              </div>
            </template>
          </k-list-item>
        </k-list>

        <!-- 用户标识 -->
        <template v-if="user?.id">
          <k-block-title>用户标识</k-block-title>
          <k-list strong inset>
            <k-list-item title="用户 ID" :subtitle="user.id" link inner-class="k-list-item-vcenter" @click="copyToClipboard(user.id)">
              <template #media>
                <span class="ios-icon-box ios-icon-gray"><IonIcon :icon="copyOutline" /></span>
              </template>
            </k-list-item>
          </k-list>
        </template>

        <!-- 操作 -->
        <k-list strong inset class="mt-4">
          <k-list-item link title="刷新信息" @click="handleRefresh">
            <template #media>
              <span class="ios-icon-box ios-icon-blue"><IonIcon :icon="refreshOutline" /></span>
            </template>
          </k-list-item>
        </k-list>

        <k-list strong inset class="mt-8">
          <k-list-item
            link
            :title="isLoggingOut ? '退出中...' : '退出登录'"
            class="k-list-item-destructive"
            @click="confirmLogout()"
          >
            <template #media>
              <span class="ios-icon-box ios-icon-red"><IonIcon :icon="logOut" /></span>
            </template>
          </k-list-item>
        </k-list>

        <div class="h-8" />
      </template>

      <!-- Modal 组件 -->
      <UserProfileDescModal
        v-model:open="isDescModalOpen"
        :auth-loading="authLoading"
        :description="displayDescription"
        :presenting-element="pageRef?.$el"
        @save="handleDescSave"
      />

      <UserProfileEmailModal
        v-model:open="isEmailModalOpen"
        :auth-loading="authLoading"
        :current-email="user?.email || ''"
        :is-email-bound="isEmailBound"
        :presenting-element="pageRef?.$el"
      />

      <UserProfilePasswordModal
        v-model:open="isPasswordModalOpen"
        :auth-loading="authLoading"
        :presenting-element="pageRef?.$el"
      />

      <UserProfileQrcodeModal
        v-model:open="isQrcodeModalOpen"
        :presenting-element="pageRef?.$el"
        :nickname="displayName"
        :description="displayDescription"
        :avatar="(userInfo.avatar || user?.avatar) || ''"
        :avatar-initial="avatarInitial"
        :user-id="user?.id"
      />
    </IonContent>
  </IonPage>
</template>
