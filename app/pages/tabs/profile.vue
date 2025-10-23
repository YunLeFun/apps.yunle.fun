<script setup lang="ts">
import {
  IonAvatar,
  IonButton,
  IonCard,
  IonCardContent,
  IonCardHeader,
  IonCardTitle,
  IonChip,
  IonCol,
  IonContent,
  IonGrid,
  IonHeader,
  IonIcon,
  IonItem,
  IonLabel,
  IonList,
  IonPage,
  IonRow,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
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

// 获取完整的用户信息
const { data: fullUserInfo, refresh: refreshUserInfo } = await useFetch('/api/wx/user')

// 计算属性
const genderIcon = computed(() => {
  if (!fullUserInfo.value?.sex)
    return helpCircleOutline
  return fullUserInfo.value.sex === 1 ? maleOutline : femaleOutline
})

const genderText = computed(() => {
  if (!fullUserInfo.value?.sex)
    return '未知'
  return fullUserInfo.value.sex === 1 ? '男' : '女'
})

const locationText = computed(() => {
  if (!fullUserInfo.value)
    return '未知'
  const { country, province, city } = fullUserInfo.value
  const parts = [country, province, city].filter(Boolean)
  return parts.length > 0 ? parts.join(' ') : '未知'
})

const hasPrivileges = computed(() => {
  return fullUserInfo.value?.privilege && fullUserInfo.value.privilege.length > 0
})

function handleLogout() {
  confirmLogout()
}

function goToSettings() {
  // TODO: 实现设置页面
  // console.log('跳转到设置页面')
}

function handleRefresh() {
  refreshUserInfo()
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
                  v-if="userInfo.avatar || fullUserInfo?.headimgurl"
                  :src="userInfo.avatar || fullUserInfo?.headimgurl"
                  :alt="userInfo.nickname || fullUserInfo?.nickname"
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

              <div class="flex items-center gap-2 text-gray-600">
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
              <IonItem v-if="fullUserInfo?.openid">
                <IonIcon slot="start" :icon="idCardOutline" />
                <IonLabel>
                  <h3>用户标识</h3>
                  <p class="text-sm font-mono">
                    {{ fullUserInfo.openid }}
                  </p>
                </IonLabel>
              </IonItem>

              <!-- UnionID -->
              <IonItem v-if="fullUserInfo?.unionid">
                <IonIcon slot="start" :icon="shieldCheckmarkOutline" />
                <IonLabel>
                  <h3>统一标识</h3>
                  <p class="text-sm font-mono">
                    {{ fullUserInfo.unionid }}
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
                v-for="privilege in fullUserInfo?.privilege"
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
