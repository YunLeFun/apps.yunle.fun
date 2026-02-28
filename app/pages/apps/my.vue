<script setup lang="ts">
import type { AppRecord } from '~/types/app'
import {
  actionSheetController,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonItem,
  IonLabel,
  IonList,
  IonPage,
  IonRefresher,
  IonRefresherContent,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { add, globe, logoGithub, trash } from 'ionicons/icons'

const router = useRouter()
const toast = useToast()
const userStore = useUserStore()
const { getMyApps, deleteApp } = useApps()

const loading = ref(true)
const myApps = ref<AppRecord[]>([])

async function fetchMyApps() {
  try {
    loading.value = true
    myApps.value = await getMyApps()
  }
  catch (err: unknown) {
    toast.showError(err instanceof Error ? err.message : '加载失败')
  }
  finally {
    loading.value = false
  }
}

async function handleRefresh(event: CustomEvent) {
  await fetchMyApps()
  ;(event.target as HTMLIonRefresherElement).complete()
}

async function handleDelete(app: AppRecord) {
  const actionSheet = await actionSheetController.create({
    header: `确认删除「${app.name}」？`,
    subHeader: '此操作不可撤销',
    buttons: [
      {
        text: '删除',
        role: 'destructive',
        handler: async () => {
          try {
            await deleteApp(app._id)
            myApps.value = myApps.value.filter(a => a._id !== app._id)
            toast.showSuccess('已删除')
          }
          catch {
            toast.showError('删除失败')
          }
        },
      },
      { text: '取消', role: 'cancel' },
    ],
  })
  await actionSheet.present()
}

function openApp(app: AppRecord) {
  if (app.websiteUrl) {
    window.open(app.websiteUrl, '_blank')
  }
}

function openGithubRepo(repo: string) {
  window.open(`https://github.com/${repo}`, '_blank')
}

function openUrl(url: string) {
  window.open(url, '_blank')
}

onMounted(() => {
  if (userStore.isLoggedIn) {
    fetchMyApps()
  }
  else {
    loading.value = false
  }
})

watch(() => userStore.isLoggedIn, (loggedIn) => {
  if (loggedIn) {
    fetchMyApps()
  }
  else {
    myApps.value = []
    loading.value = false
  }
})
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonTitle>我的应用</IonTitle>
        <IonButtons slot="end">
          <IonButton v-if="userStore.isLoggedIn" @click="router.push('/apps/new')">
            <IonIcon slot="icon-only" :icon="add" />
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <IonHeader collapse="condense">
        <IonToolbar>
          <IonTitle size="large">
            我的应用
          </IonTitle>
        </IonToolbar>
      </IonHeader>

      <IonRefresher slot="fixed" @ion-refresh="handleRefresh">
        <IonRefresherContent />
      </IonRefresher>

      <!-- 未登录提示 -->
      <div v-if="!userStore.isLoggedIn" class="flex flex-col items-center justify-center gap-4 px-6 pt-20">
        <p class="text-center text-base opacity-50">
          登录后可以创建和管理你的应用
        </p>
        <IonButton fill="solid" @click="router.push('/login')">
          去登录
        </IonButton>
      </div>

      <!-- 加载中 -->
      <div v-else-if="loading" class="flex justify-center pt-20">
        <div class="i-lucide-loader-2 text-3xl animate-spin opacity-40" />
      </div>

      <!-- 空状态 -->
      <div v-else-if="myApps.length === 0" class="flex flex-col items-center justify-center gap-4 px-6 pt-20">
        <div class="text-5xl opacity-30">
          📦
        </div>
        <p class="text-center text-base opacity-50">
          还没有应用，创建一个吧
        </p>
        <IonButton fill="solid" @click="router.push('/apps/new')">
          创建应用
        </IonButton>
      </div>

      <!-- 应用列表 -->
      <IonList v-else inset>
        <IonItem
          v-for="app in myApps"
          :key="app._id"
          button
          :detail="false"
          @click="openApp(app)"
        >
          <!-- 图标 -->
          <div slot="start" class="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-lg">
            {{ app.icon || '📱' }}
          </div>

          <IonLabel>
            <h2 class="font-medium">
              {{ app.name }}
            </h2>
            <p v-if="app.description" class="line-clamp-1 text-xs opacity-60">
              {{ app.description }}
            </p>
            <div v-if="app.category || (app.tags && app.tags.length)" class="mt-1 flex flex-wrap gap-1">
              <span
                v-if="app.category"
                class="rounded-full bg-primary/10 px-2 py-0.5 text-2xs text-primary"
              >
                {{ app.category }}
              </span>
              <span
                v-for="tag in (app.tags || []).slice(0, 3)"
                :key="tag"
                class="rounded-full bg-gray-100 px-2 py-0.5 text-2xs opacity-60 dark:bg-gray-800"
              >
                {{ tag }}
              </span>
            </div>
          </IonLabel>

          <!-- 操作按钮 -->
          <IonButtons slot="end">
            <IonButton v-if="app.githubRepo" size="small" fill="clear" @click.stop="openGithubRepo(app.githubRepo!)">
              <IonIcon slot="icon-only" :icon="logoGithub" size="small" />
            </IonButton>
            <IonButton v-if="app.websiteUrl" size="small" fill="clear" @click.stop="openUrl(app.websiteUrl!)">
              <IonIcon slot="icon-only" :icon="globe" size="small" />
            </IonButton>
            <IonButton size="small" fill="clear" color="danger" @click.stop="handleDelete(app)">
              <IonIcon slot="icon-only" :icon="trash" size="small" />
            </IonButton>
          </IonButtons>
        </IonItem>
      </IonList>

      <!-- 底部信息 -->
      <div v-if="userStore.isLoggedIn && myApps.length > 0" class="px-6 pb-8 pt-2 text-center text-xs opacity-40">
        共 {{ myApps.length }} 个应用
      </div>
    </IonContent>
  </IonPage>
</template>
