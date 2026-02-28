<script setup lang="ts">
import { actionSheetController, alertController } from '@ionic/vue'
import {
  callOutline,
  checkmarkCircle,
  closeCircle,
  copyOutline,
  keyOutline,
  lockClosedOutline,
  logOut,
  logoGithub,
  logoWechat,
  mailOutline,
  personOutline,
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
const toast = useToast()

const {
  user,
  loading: authLoading,
  fetchUser,
  updateUserInfo,
  unlinkProvider,
  linkProvider,
  resetPasswordWithOld,
  changeEmail,
  verifyEmailBindOtp,
} = useCloudbaseAuth()

await fetchUser()

// === 计算属性 ===
const displayName = computed(() =>
  user.value?.nickname || userInfo.value.nickname || '未设置',
)
const displayDescription = computed(() => user.value?.description || '')
const displayPhone = computed(() => {
  const phone = user.value?.phone
  if (!phone)
    return '未绑定'
  return phone.replace(/(\d{3})\d{4}(\d{4})/, '$1****$2')
})
const displayEmail = computed(() => user.value?.email || '未绑定')
const joinDate = computed(() => {
  const date = user.value?.createdAt
  if (!date)
    return '未知'
  return new Date(date).toLocaleDateString('zh-CN', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  })
})
const avatarInitial = computed(() => (displayName.value || '云')[0])
const isGitHubBound = computed(() => user.value?.providers?.includes('github'))
const isWeChatBound = computed(() => user.value?.providers?.includes('wx_open'))
const isPhoneBound = computed(() => !!user.value?.phone)
const isEmailBound = computed(() => !!user.value?.email)
const hasPassword = computed(() => user.value?.hasPassword ?? false)
const displayGender = computed(() => {
  const g = user.value?.gender
  if (g === 'MALE')
    return '男'
  if (g === 'FEMALE')
    return '女'
  return '未设置'
})

// === 编辑昵称 ===
async function editNickname() {
  const alert = await alertController.create({
    header: '修改昵称',
    inputs: [
      {
        name: 'nickname',
        type: 'text',
        placeholder: '请输入昵称',
        value: user.value?.nickname || '',
        attributes: { maxlength: 20 },
      },
    ],
    buttons: [
      { text: '取消', role: 'cancel' },
      {
        text: '完成',
        handler: async (data) => {
          const val = data.nickname?.trim()
          if (!val || val === (user.value?.nickname || ''))
            return
          await updateUserInfo({ nickname: val } as any)
        },
      },
    ],
  })
  await alert.present()
}

// === 编辑简介 ===
const isDescModalOpen = ref(false)
const descEditValue = ref('')

function openDescModal() {
  descEditValue.value = user.value?.description || ''
  isDescModalOpen.value = true
}

async function saveDesc() {
  const val = descEditValue.value.trim()
  if (val === (user.value?.description || '')) {
    isDescModalOpen.value = false
    return
  }
  const success = await updateUserInfo({ description: val } as any)
  if (success)
    isDescModalOpen.value = false
}

// === 编辑性别 ===
async function editGender() {
  const actionSheet = await actionSheetController.create({
    header: '选择性别',
    buttons: [
      {
        text: '男',
        handler: () => updateUserInfo({ gender: 'MALE' } as any),
      },
      {
        text: '女',
        handler: () => updateUserInfo({ gender: 'FEMALE' } as any),
      },
      {
        text: '未设置',
        handler: () => updateUserInfo({ gender: '' } as any),
      },
      { text: '取消', role: 'cancel' },
    ],
  })
  await actionSheet.present()
}

// === 手机号提示 ===
function handlePhoneTap() {
  toast.showInfo('手机号暂不支持换绑')
}

// === 换绑邮箱 ===
const isEmailModalOpen = ref(false)
const emailForm = reactive({
  newEmail: '',
  verifyCode: '',
})
const emailVerifyFn = ref<((params: { email: string, token: string }) => Promise<unknown>) | null>(null)
const emailStep = ref<'input' | 'verify'>('input')

function openEmailModal() {
  emailForm.newEmail = ''
  emailForm.verifyCode = ''
  emailVerifyFn.value = null
  emailStep.value = 'input'
  isEmailModalOpen.value = true
}

async function submitEmailChange() {
  if (!emailForm.newEmail.trim()) {
    toast.showWarning('请输入邮箱地址')
    return
  }
  const result = await changeEmail(emailForm.newEmail.trim())
  if (!result)
    return
  if (result.needVerify && result.verifyOtp) {
    emailVerifyFn.value = result.verifyOtp as any
    emailStep.value = 'verify'
  }
  else {
    isEmailModalOpen.value = false
  }
}

async function submitEmailVerify() {
  if (!emailForm.verifyCode.trim()) {
    toast.showWarning('请输入验证码')
    return
  }
  if (!emailVerifyFn.value)
    return
  const ok = await verifyEmailBindOtp(emailVerifyFn.value, emailForm.newEmail, emailForm.verifyCode.trim())
  if (ok)
    isEmailModalOpen.value = false
}

// === 重设密码 ===
const isPasswordModalOpen = ref(false)
const passwordForm = reactive({
  oldPassword: '',
  newPassword: '',
  confirmPassword: '',
})

function openPasswordModal() {
  passwordForm.oldPassword = ''
  passwordForm.newPassword = ''
  passwordForm.confirmPassword = ''
  isPasswordModalOpen.value = true
}

async function submitPasswordChange() {
  if (!passwordForm.oldPassword) {
    toast.showWarning('请输入当前密码')
    return
  }
  if (!passwordForm.newPassword || passwordForm.newPassword.length < 8) {
    toast.showWarning('新密码至少 8 位')
    return
  }
  if (passwordForm.newPassword !== passwordForm.confirmPassword) {
    toast.showWarning('两次密码不一致')
    return
  }
  const ok = await resetPasswordWithOld(passwordForm.oldPassword, passwordForm.newPassword)
  if (ok)
    isPasswordModalOpen.value = false
}

// === 绑定/解绑微信 ===
async function handleWeChatTap() {
  if (isWeChatBound.value) {
    const alert = await alertController.create({
      header: '解绑微信',
      message: '确定要解绑微信账号吗？解绑后将无法通过微信登录。',
      buttons: [
        { text: '取消', role: 'cancel' },
        {
          text: '解绑',
          role: 'destructive',
          handler: () => unlinkProvider('wx_open'),
        },
      ],
    })
    await alert.present()
  }
  else {
    await linkProvider('wx_open')
  }
}

// === 绑定/解绑 GitHub ===
async function handleGitHubTap() {
  if (isGitHubBound.value) {
    const alert = await alertController.create({
      header: '解绑 GitHub',
      message: '确定要解绑 GitHub 账号吗？解绑后将无法通过 GitHub 登录。',
      buttons: [
        { text: '取消', role: 'cancel' },
        {
          text: '解绑',
          role: 'destructive',
          handler: () => unlinkProvider('github'),
        },
      ],
    })
    await alert.present()
  }
  else {
    await linkProvider('github')
  }
}

// === 工具 ===
async function copyToClipboard(text: string) {
  try {
    await navigator.clipboard.writeText(text)
    toast.showSuccess('已复制')
  }
  catch { /* silent */ }
}

async function handleRefresh() {
  await fetchUser()
  toast.showSuccess('已刷新')
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
              <img
                v-if="userInfo.avatar || user?.avatar"
                :src="(userInfo.avatar || user?.avatar)!"
                :alt="displayName"
                class="h-full w-full object-cover"
              >
              <div v-else class="h-full w-full flex items-center justify-center ios-avatar-bg">
                <span class="text-2xl font-semibold text-white">{{ avatarInitial }}</span>
              </div>
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

          <k-list-item title="个人简介" link @click="openDescModal">
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

          <k-list-item title="邮箱" link @click="openEmailModal">
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
          <k-list-item title="登录密码" :link="hasPassword" @click="hasPassword && openPasswordModal()">
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
            <k-list-item title="用户 ID" :subtitle="user.id" link @click="copyToClipboard(user.id)">
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

      <!-- 编辑简介 Sheet Modal -->
      <IonModal
        :is-open="isDescModalOpen"
        :initial-breakpoint="0.45"
        :breakpoints="[0, 0.45, 0.75]"
        :handle="true"
        @did-dismiss="isDescModalOpen = false"
      >
        <IonHeader>
          <IonToolbar>
            <IonButtons slot="start">
              <IonButton @click="isDescModalOpen = false">
                取消
              </IonButton>
            </IonButtons>
            <IonTitle>编辑简介</IonTitle>
            <IonButtons slot="end">
              <IonButton :strong="true" :disabled="authLoading" @click="saveDesc">
                完成
              </IonButton>
            </IonButtons>
          </IonToolbar>
        </IonHeader>
        <IonContent>
          <IonList :inset="true" class="mt-4">
            <IonItem>
              <IonTextarea
                v-model="descEditValue"
                label="个人简介"
                label-placement="stacked"
                placeholder="介绍一下自己吧"
                :maxlength="200"
                :auto-grow="true"
                :rows="3"
                :counter="true"
              />
            </IonItem>
          </IonList>
        </IonContent>
      </IonModal>

      <!-- 换绑邮箱 Sheet Modal -->
      <IonModal
        :is-open="isEmailModalOpen"
        :initial-breakpoint="0.45"
        :breakpoints="[0, 0.45, 0.75]"
        :handle="true"
        @did-dismiss="isEmailModalOpen = false"
      >
        <IonHeader>
          <IonToolbar>
            <IonButtons slot="start">
              <IonButton @click="isEmailModalOpen = false">
                取消
              </IonButton>
            </IonButtons>
            <IonTitle>{{ isEmailBound ? '换绑邮箱' : '绑定邮箱' }}</IonTitle>
            <IonButtons slot="end">
              <IonButton
                :strong="true"
                :disabled="authLoading"
                @click="emailStep === 'input' ? submitEmailChange() : submitEmailVerify()"
              >
                {{ emailStep === 'input' ? '发送验证' : '确认' }}
              </IonButton>
            </IonButtons>
          </IonToolbar>
        </IonHeader>
        <IonContent>
          <IonList :inset="true" class="mt-4">
            <template v-if="emailStep === 'input'">
              <IonItem v-if="user?.email">
                <IonInput
                  :value="user.email"
                  label="当前邮箱"
                  label-placement="stacked"
                  :readonly="true"
                />
              </IonItem>
              <IonItem>
                <IonInput
                  v-model="emailForm.newEmail"
                  label="新邮箱"
                  label-placement="stacked"
                  type="email"
                  placeholder="请输入新邮箱地址"
                  :clear-input="true"
                  inputmode="email"
                />
              </IonItem>
            </template>
            <template v-else>
              <IonItem>
                <IonInput
                  :value="emailForm.newEmail"
                  label="新邮箱"
                  label-placement="stacked"
                  :readonly="true"
                />
              </IonItem>
              <IonItem>
                <IonInput
                  v-model="emailForm.verifyCode"
                  label="验证码"
                  label-placement="stacked"
                  placeholder="请输入邮箱验证码"
                  inputmode="numeric"
                  :maxlength="6"
                  :clear-input="true"
                />
              </IonItem>
            </template>
          </IonList>
          <div v-if="emailStep === 'verify'" class="px-6 mt-2">
            <p class="text-xs ios-secondary-text">
              验证码已发送至 {{ emailForm.newEmail }}，请查收邮件。
            </p>
          </div>
        </IonContent>
      </IonModal>

      <!-- 重设密码 Sheet Modal -->
      <IonModal
        :is-open="isPasswordModalOpen"
        :initial-breakpoint="0.55"
        :breakpoints="[0, 0.55, 0.85]"
        :handle="true"
        @did-dismiss="isPasswordModalOpen = false"
      >
        <IonHeader>
          <IonToolbar>
            <IonButtons slot="start">
              <IonButton @click="isPasswordModalOpen = false">
                取消
              </IonButton>
            </IonButtons>
            <IonTitle>重设密码</IonTitle>
            <IonButtons slot="end">
              <IonButton :strong="true" :disabled="authLoading" @click="submitPasswordChange">
                完成
              </IonButton>
            </IonButtons>
          </IonToolbar>
        </IonHeader>
        <IonContent>
          <IonList :inset="true" class="mt-4">
            <IonItem>
              <IonInput
                v-model="passwordForm.oldPassword"
                label="当前密码"
                label-placement="stacked"
                type="password"
                placeholder="请输入当前密码"
                :clear-input="true"
              />
            </IonItem>
            <IonItem>
              <IonInput
                v-model="passwordForm.newPassword"
                label="新密码"
                label-placement="stacked"
                type="password"
                placeholder="至少 8 位"
                :clear-input="true"
              />
            </IonItem>
            <IonItem>
              <IonInput
                v-model="passwordForm.confirmPassword"
                label="确认新密码"
                label-placement="stacked"
                type="password"
                placeholder="请再次输入新密码"
                :clear-input="true"
              />
            </IonItem>
          </IonList>
          <div class="px-6 mt-2">
            <p class="text-xs ios-secondary-text flex items-center gap-1">
              <IonIcon :icon="lockClosedOutline" class="text-xs" />
              密码修改后，所有设备需重新登录。
            </p>
          </div>
        </IonContent>
      </IonModal>
    </IonContent>
  </IonPage>
</template>
