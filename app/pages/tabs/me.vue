<script setup lang="ts">
import {
  IonContent,
  IonHeader,
  IonPage,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { apps, chatbubbleEllipsesOutline, codeSlashOutline, flagOutline, helpCircleOutline, informationCircle, peopleOutline, personCircleOutline, ribbonOutline, settings, storefrontOutline, swapHorizontalOutline, walletOutline } from 'ionicons/icons'
import {
  kList,
  kListItem,
} from 'konsta/vue'

const router = useRouter()

const userStore = useUserStore()
const developerStore = useDeveloperStore()
const accountsStore = useAccountsStore()
const { account, balance, isMember, refresh: refreshAccount } = useCoin()

const otherAccounts = computed(() =>
  accountsStore.getOtherAccounts(userStore.userInfo?.id),
)

onMounted(() => {
  if (userStore.isLoggedIn)
    refreshAccount()
})

function goToLoginPage() {
  router.push('/login')
}

function navigateTo(path: string) {
  router.push(path)
}

async function logoutNativeTestSession() {
  userStore.clearNativeTestSession()
  await router.push('/login')
}
</script>

<template>
  <IonPage>
    <IonHeader>
      <IonToolbar>
        <IonTitle>我的</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent>
      <div class="me-page-content">
        <!-- 未登录：登录入口（iOS Settings Apple ID 风格） -->
        <k-list v-if="!userStore.isLoggedIn && !userStore.isNativeTestLoggedIn" strong inset>
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

        <!-- 原生测试身份：只展示授权能力，不解锁业务功能 -->
        <k-list v-else-if="userStore.isNativeTestLoggedIn" strong inset>
          <k-list-item
            :title="userStore.nativeTestSession?.account.publicAlias"
            :footer="`${userStore.nativeTestSession?.account.virtualPhone} · 仅限云笺原生登录验证`"
            inner-class="k-list-item-vcenter"
          >
            <template #media>
              <IonIcon :icon="personCircleOutline" class="text-5xl" color="primary" />
            </template>
          </k-list-item>
        </k-list>

        <!-- 已登录：真实用户信息 -->
        <k-list v-else strong inset>
          <k-list-item
            link
            :title="userInfo.nickname || '云乐坊用户'"
            footer="查看个人资料"
            inner-class="k-list-item-vcenter"
            @click="navigateTo('/user/profile')"
          >
            <template #media>
              <UserAvatar
                :src="userInfo.avatar"
                :alt="userInfo.nickname"
                telemetry-surface="tabs.me"
                class="h-14 w-14 rounded-full object-cover"
              >
                <template #fallback>
                  <div class="ios-icon-avatar">
                    <span class="text-xl text-white font-semibold">
                      {{ (userInfo.nickname || '云')[0] }}
                    </span>
                  </div>
                </template>
              </UserAvatar>
            </template>
          </k-list-item>
        </k-list>

        <!-- 钱包（登录后可见） -->
        <k-list v-if="userStore.isLoggedIn" strong inset>
          <k-list-item
            link
            title="我的个人工坊"
            subtitle="开启或管理二维码、加入方式和坊客"
            :strong-title="false"
            inner-class="k-list-item-vcenter"
            @click="navigateTo('/user/workshop')"
          >
            <template #media>
              <span class="ios-icon-box ios-icon-blue">
                <IonIcon :icon="storefrontOutline" />
              </span>
            </template>
          </k-list-item>

          <k-list-item
            link
            title="已加入的工坊"
            subtitle="查看坊客专属作品"
            :strong-title="false"
            inner-class="k-list-item-vcenter"
            @click="navigateTo('/user/workshops')"
          >
            <template #media>
              <span class="ios-icon-box ios-icon-orange">
                <IonIcon :icon="peopleOutline" />
              </span>
            </template>
          </k-list-item>

          <k-list-item
            link
            title="钱包"
            subtitle="云币 & 流水"
            :strong-title="false"
            inner-class="k-list-item-vcenter"
            @click="navigateTo('/wallet')"
          >
            <template #media>
              <span class="ios-icon-box ios-icon-orange">
                <IonIcon :icon="walletOutline" />
              </span>
            </template>
            <template #after>
              <span v-if="account" class="wallet-balance">{{ balance }} 云币</span>
              <span v-else class="wallet-balance-skeleton" />
            </template>
          </k-list-item>

          <k-list-item
            link
            title="会员"
            :subtitle="isMember ? '会员有效中' : '解锁更多权益'"
            :strong-title="false"
            inner-class="k-list-item-vcenter"
            @click="navigateTo('/membership')"
          >
            <template #media>
              <span class="ios-icon-box ios-icon-purple">
                <IonIcon :icon="ribbonOutline" />
              </span>
            </template>
            <template #after>
              <span v-if="isMember" class="member-active-badge">有效</span>
            </template>
          </k-list-item>
        </k-list>

        <!-- 我的应用 / 我的举报（登录后可见） -->
        <k-list v-if="userStore.isLoggedIn" strong inset>
          <k-list-item
            link
            title="我的应用"
            subtitle="创建和管理你的应用"
            :strong-title="false"
            inner-class="k-list-item-vcenter"
            @click="navigateTo('/workshop')"
          >
            <template #media>
              <span class="ios-icon-box ios-icon-blue">
                <IonIcon :icon="apps" />
              </span>
            </template>
          </k-list-item>

          <k-list-item
            link
            title="我的举报"
            subtitle="查看举报处理进度"
            :strong-title="false"
            inner-class="k-list-item-vcenter"
            @click="navigateTo('/user/reports')"
          >
            <template #media>
              <span class="ios-icon-box ios-icon-red">
                <IonIcon :icon="flagOutline" />
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
        <k-list v-if="userStore.isLoggedIn" strong inset class="me-signout-list">
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
        <k-list v-else-if="userStore.isNativeTestLoggedIn" strong inset class="me-signout-list">
          <k-list-item
            link
            title="退出测试身份"
            footer="也可以在云笺授权弹窗中选择其他账号"
            @click="logoutNativeTestSession"
          >
            <template #media>
              <span class="ios-icon-box ios-icon-blue">
                <IonIcon :icon="swapHorizontalOutline" />
              </span>
            </template>
          </k-list-item>
        </k-list>
      </div>
    </IonContent>
  </IonPage>
</template>

<style scoped>
/*
 * Konsta k-list 第一个 list 紧贴 header 时视觉缺少呼吸感，
 * 增加顶部 padding 补偿（原 large title 移除后的空间填补）
 */
.me-page-content {
  padding-top: 12px;
  padding-bottom: 32px;
}

/* 退出/切换账号组与上方保持更大间距 */
.me-signout-list {
  margin-top: 32px !important;
}

.wallet-balance {
  display: block;
  max-width: min(46vw, 200px);
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 15px;
  font-weight: 600;
  color: var(--ion-color-warning, #ff9f0a);
}

/* 余额骨架占位（仅本地无缓存的首次加载出现） */
.wallet-balance-skeleton {
  display: inline-block;
  width: 64px;
  height: 16px;
  border-radius: 6px;
  background: var(--ylf-fill-tertiary);
  animation: wallet-balance-pulse 1.5s ease-in-out infinite;
}

@keyframes wallet-balance-pulse {
  0%,
  100% {
    opacity: 1;
  }
  50% {
    opacity: 0.4;
  }
}

/* 会员有效徽标 */
.member-active-badge {
  font-size: 13px;
  font-weight: 600;
  color: var(--ion-color-success, #2dd36f);
}
</style>
