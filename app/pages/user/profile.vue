<script setup lang="ts">
import type { YlfUserInfo } from '~~/packages/auth/src'
import {
  calendarOutline,
  chevronForwardOutline,
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

const router = useRouter()
const userStore = useUserStore()
const { confirmLogout, isLoggingOut } = useLogout()

const { $api } = useNuxtApp()
// 获取完整的用户信息
const fullUserInfo = ref<YlfUserInfo | null>(null)
const isLoading = ref(false)

// 加载用户信息
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

// 初始加载
await loadUserInfo()

// 性别选择
const isEditingGender = ref(false)
const selectedGender = ref<0 | 1 | 2>(fullUserInfo.value?.profile?.sex ?? 0)

// 计算属性
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

function goToSettings() {
  // TODO: 实现设置页面
  // console.log('跳转到设置页面')
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
    // TODO: 调用 API 更新性别
    // await $api('/auth/profile', {
    //   method: 'PATCH',
    //   body: { sex: selectedGender.value }
    // })

    // 暂时只更新本地状态
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
    <IonHeader>
      <IonToolbar>
        <IonTitle>个人资料</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent class="ion-padding">
      <!-- 未登录状态 -->
      <div v-if="!userStore.isLoggedIn" class="h-full flex flex-col items-center justify-center">
        <IonIcon :icon="person" class="mb-4 text-6xl text-gray-400" />
        <p class="mb-6 text-gray-500">
          请先登录查看个人资料
        </p>
        <IonButton
          expand="block"
          @click="router.push('/login')"
        >
          去登录
        </IonButton>
      </div>

      <!-- 已登录状态 -->
      <div v-else>
        <!-- 用户头像和基本信息 -->
        <IonCard>
          <IonCardContent>
            <div class="flex flex-col items-center text-center">
              <IonAvatar class="mb-4 h-24 w-24">
                <img
                  v-if="userInfo.avatar || fullUserInfo?.profile?.headimgurl"
                  :src="userInfo.avatar || fullUserInfo?.profile?.headimgurl"
                  :alt="userInfo.nickname || fullUserInfo?.profile?.nickname"
                >
                <IonIcon
                  v-else
                  :icon="person"
                  class="text-4xl"
                />
              </IonAvatar>

              <h2 class="mb-2 text-xl font-bold">
                {{ userInfo.nickname || fullUserInfo?.nickname || '无名氏' }}
              </h2>

              <div class="flex cursor-pointer items-center gap-2 text-gray-600" @click="openGenderSelect">
                <IonIcon :icon="genderIcon" />
                <span>{{ genderText }}</span>
              </div>
            </div>
          </IonCardContent>
        </IonCard>

        <!-- 详细信息 -->
        <IonCard>
          <IonCardHeader>
            <IonCardTitle>详细信息</IonCardTitle>
          </IonCardHeader>
          <IonCardContent>
            <IonList>
              <!-- 地理位置 -->
              <IonItem>
                <IonIcon slot="start" :icon="locationOutline" />
                <IonLabel>
                  <h3>地理位置</h3>
                  <p>{{ locationText }}</p>
                </IonLabel>
              </IonItem>

              <!-- OpenID -->
              <IonItem v-if="fullUserInfo?.profile?.openid">
                <IonIcon slot="start" :icon="idCardOutline" />
                <IonLabel>
                  <h3>用户标识</h3>
                  <p class="text-sm font-mono">
                    {{ fullUserInfo.profile.openid }}
                  </p>
                </IonLabel>
              </IonItem>

              <!-- UnionID -->
              <IonItem v-if="fullUserInfo?.profile?.unionid">
                <IonIcon slot="start" :icon="shieldCheckmarkOutline" />
                <IonLabel>
                  <h3>统一标识</h3>
                  <p class="text-sm font-mono">
                    {{ fullUserInfo.profile.unionid }}
                  </p>
                </IonLabel>
              </IonItem>
            </IonList>
          </IonCardContent>
        </IonCard>

        <!-- 特权信息 -->
        <IonCard v-if="hasPrivileges">
          <IonCardHeader>
            <IonCardTitle>特权信息</IonCardTitle>
          </IonCardHeader>
          <IonCardContent>
            <div class="flex flex-wrap gap-2">
              <IonChip
                v-for="privilege in fullUserInfo?.profile?.privilege"
                :key="privilege"
                color="primary"
              >
                <IonLabel>{{ privilege }}</IonLabel>
              </IonChip>
            </div>
          </IonCardContent>
        </IonCard>

        <!-- 账户统计 -->
        <IonCard>
          <IonCardHeader>
            <IonCardTitle>账户统计</IonCardTitle>
          </IonCardHeader>
          <IonCardContent>
            <IonGrid>
              <IonRow>
                <IonCol size="6" class="text-center">
                  <div class="text-primary text-2xl font-bold">
                    {{ userStore.accessToken ? '已认证' : '未认证' }}
                  </div>
                  <div class="text-sm text-gray-600">
                    认证状态
                  </div>
                </IonCol>
                <IonCol size="6" class="text-center">
                  <div class="text-primary text-2xl font-bold">
                    {{ new Date().toLocaleDateString() }}
                  </div>
                  <div class="text-sm text-gray-600">
                    最后登录
                  </div>
                </IonCol>
              </IonRow>
            </IonGrid>
          </IonCardContent>
        </IonCard>

        <!-- 操作按钮 -->
        <IonCard>
          <IonCardContent>
            <IonList>
              <IonItem button @click="handleRefresh">
                <IonIcon slot="start" :icon="calendarOutline" />
                <IonLabel>刷新信息</IonLabel>
                <IonIcon slot="end" :icon="chevronForwardOutline" />
              </IonItem>

              <IonItem button @click="goToSettings">
                <IonIcon slot="start" :icon="settingsOutline" />
                <IonLabel>设置</IonLabel>
                <IonIcon slot="end" :icon="chevronForwardOutline" />
              </IonItem>

              <IonItem
                button
                :disabled="isLoggingOut"
                @click="handleLogout"
              >
                <IonIcon slot="start" :icon="logOut" />
                <IonLabel>{{ isLoggingOut ? '退出中...' : '退出登录' }}</IonLabel>
                <IonIcon slot="end" :icon="chevronForwardOutline" />
              </IonItem>
            </IonList>
          </IonCardContent>
        </IonCard>
      </div>

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
          <IonList>
            <IonItem button @click="selectedGender = 1; handleGenderChange()">
              <IonIcon slot="start" :icon="maleOutline" />
              <IonLabel>男</IonLabel>
              <IonIcon v-if="selectedGender === 1" slot="end" name="checkmark" color="primary" />
            </IonItem>
            <IonItem button @click="selectedGender = 2; handleGenderChange()">
              <IonIcon slot="start" :icon="femaleOutline" />
              <IonLabel>女</IonLabel>
              <IonIcon v-if="selectedGender === 2" slot="end" name="checkmark" color="primary" />
            </IonItem>
            <IonItem button @click="selectedGender = 0; handleGenderChange()">
              <IonIcon slot="start" :icon="helpCircleOutline" />
              <IonLabel>保密</IonLabel>
              <IonIcon v-if="selectedGender === 0" slot="end" name="checkmark" color="primary" />
            </IonItem>
          </IonList>
        </IonContent>
      </IonModal>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.w-24 {
  width: 6rem;
}

.h-24 {
  height: 6rem;
}

.h-full {
  height: 100%;
}
</style>
