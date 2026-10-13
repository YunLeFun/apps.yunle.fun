<script setup lang="ts">
import {
  IonBackButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonPage,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { addOutline, checkmarkCircle, logOut, personOutline, trashOutline } from 'ionicons/icons'
import {
  kList,
  kListItem,
} from 'konsta/vue'

const router = useRouter()
const userStore = useUserStore()
const accountsStore = useAccountsStore()
const { confirmLogout, isLoggingOut } = useLogout()

const currentUid = computed(() => userStore.userInfo?.id)

const savedAccounts = computed(() => accountsStore.accounts)

function handleSwitchAccount(account: typeof savedAccounts.value[0]) {
  if (account.uid === currentUid.value)
    return
  // 先退出当前账号，然后跳到登录页预填信息
  // 由于 CloudBase Auth 不支持直接切换 session，需先登出再登录
  router.push({
    path: '/login',
    query: {
      switchTo: account.uid,
      method: account.lastLoginMethod || '',
    },
  })
}

function handleAddAccount() {
  router.push('/login')
}

function handleRemoveAccount(uid: string) {
  accountsStore.removeAccount(uid)
}

function handleLogout() {
  confirmLogout()
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" text="返回" />
        </IonButtons>
        <IonTitle>账号管理</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <IonHeader collapse="condense">
        <IonToolbar>
          <IonTitle size="large">
            账号管理
          </IonTitle>
        </IonToolbar>
      </IonHeader>

      <!-- 当前登录的账号 -->
      <k-list v-if="userStore.isLoggedIn && userStore.userInfo" strong inset class="mt-1">
        <k-list-item
          :title="userStore.userInfo.nickname || '云乐坊用户'"
          footer="当前登录"
          inner-class="k-list-item-vcenter"
        >
          <template #media>
            <UserAvatar
              :src="userStore.userInfo.avatar"
              :alt="userStore.userInfo.nickname"
              telemetry-surface="accounts.current"
              class="h-12 w-12 rounded-full object-cover"
            >
              <template #fallback>
                <div class="account-avatar-placeholder">
                  <IonIcon :icon="personOutline" />
                </div>
              </template>
            </UserAvatar>
          </template>
          <template #after>
            <IonIcon :icon="checkmarkCircle" class="text-xl text---ion-color-primary" />
          </template>
        </k-list-item>
      </k-list>

      <!-- 其他已保存的账号 -->
      <k-list
        v-if="savedAccounts.filter(a => a.uid !== currentUid).length > 0"
        strong
        inset
      >
        <template #header>
          <span class="pl-1">其他已保存的账号</span>
        </template>
        <k-list-item
          v-for="account in savedAccounts.filter(a => a.uid !== currentUid)"
          :key="account.uid"
          link
          :title="account.nickname || '云乐坊用户'"
          :footer="account.phone || account.email || '点击切换到此账号'"
          inner-class="k-list-item-vcenter"
          @click="handleSwitchAccount(account)"
        >
          <template #media>
            <UserAvatar
              :src="account.avatar"
              :alt="account.nickname"
              telemetry-surface="accounts.saved"
              class="h-10 w-10 rounded-full object-cover"
            >
              <template #fallback>
                <div class="account-avatar-placeholder account-avatar-sm">
                  <IonIcon :icon="personOutline" />
                </div>
              </template>
            </UserAvatar>
          </template>
          <template #after>
            <button
              class="account-remove-btn"
              @click.stop="handleRemoveAccount(account.uid)"
            >
              <IonIcon :icon="trashOutline" />
            </button>
          </template>
        </k-list-item>
      </k-list>

      <!-- 添加账号 -->
      <k-list strong inset>
        <k-list-item
          link
          title="添加其他账号"
          @click="handleAddAccount"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-blue">
              <IonIcon :icon="addOutline" />
            </span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 退出登录 -->
      <k-list v-if="userStore.isLoggedIn" strong inset class="mt-8">
        <k-list-item
          link
          :title="isLoggingOut ? '退出中...' : '退出当前账号'"
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

<style lang="scss" scoped>
.account-avatar-placeholder {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 48px;
  height: 48px;
  border-radius: 50%;
  background: #e5e5ea;
  color: var(--ion-color-medium, #8e8e93);
  font-size: 22px;

  .dark & {
    background: #39393d;
  }

  &.account-avatar-sm {
    width: 40px;
    height: 40px;
    font-size: 18px;
  }
}

.account-remove-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  background: none;
  border: none;
  color: var(--ion-color-danger, #ff3b30);
  font-size: 18px;
  cursor: pointer;
  border-radius: 50%;
  -webkit-tap-highlight-color: transparent;

  &:active {
    opacity: 0.5;
  }
}
</style>
