<script setup lang="ts">
import type { AppRecord } from '~/types/app'
import type { WorkshopView } from '~/types/workshop'
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonItem,
  IonLabel,
  IonList,
  IonNote,
  IonPage,
  IonSpinner,
  IonTitle,
  IonToolbar,
  onIonViewWillEnter,
} from '@ionic/vue'
import {
  chevronForwardOutline,
  lockClosedOutline,
  logInOutline,
  logOutOutline,
  peopleOutline,
  settingsOutline,
} from 'ionicons/icons'

const route = useRoute()
const router = useRouter()
const userStore = useUserStore()
const toast = useToast()
const workshopModule = usePersonalWorkshop()

const workshopId = computed(() => {
  const raw = route.params.id
  return (Array.isArray(raw) ? raw[0] : raw || '').toUpperCase()
})
const view = ref<WorkshopView | null>(null)
const loading = ref(true)
const acting = ref(false)
const error = ref('')

async function load() {
  if (!workshopId.value)
    return
  loading.value = true
  error.value = ''
  try {
    view.value = await workshopModule.getView(workshopId.value)
  }
  catch (reason: unknown) {
    view.value = null
    error.value = reason instanceof Error ? reason.message : '个人工坊加载失败'
  }
  finally {
    loading.value = false
  }
}

async function handleJoin() {
  if (!userStore.isLoggedIn) {
    await router.push({
      path: '/login',
      query: { redirect: route.fullPath },
    })
    return
  }
  acting.value = true
  try {
    const result = await workshopModule.join(workshopId.value)
    toast.showSuccess(result.joined ? '已加入个人工坊' : '加入申请已提交')
    await load()
  }
  catch (reason: unknown) {
    toast.showError(reason instanceof Error ? reason.message : '暂时无法加入')
  }
  finally {
    acting.value = false
  }
}

async function handleLeave() {
  acting.value = true
  try {
    await workshopModule.leave(workshopId.value)
    toast.showSuccess('已退出个人工坊')
    await load()
  }
  catch (reason: unknown) {
    toast.showError(reason instanceof Error ? reason.message : '退出失败')
  }
  finally {
    acting.value = false
  }
}

function openApp(app: AppRecord) {
  if (app.websiteUrl)
    openInAppBrowser(app.websiteUrl, { trustedHosts: app.trustedHosts })
}

const canRequest = computed(() =>
  view.value
  && view.value.workshop.status === 'active'
  && view.value.workshop.joinPolicy !== 'closed'
  && ['anonymous', 'none'].includes(view.value.access),
)

onIonViewWillEnter(load)
watch(() => userStore.isLoggedIn, load)
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/apps" text="" />
        </IonButtons>
        <IonTitle>个人工坊</IonTitle>
        <IonButtons v-if="view?.access === 'owner'" slot="end">
          <IonButton @click="router.push('/user/workshop')">
            <IonIcon slot="icon-only" :icon="settingsOutline" />
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true" class="workshop-content">
      <div v-if="loading" class="workshop-loading">
        <IonSpinner name="crescent" />
      </div>

      <div v-else-if="error" class="workshop-message">
        <IonIcon :icon="lockClosedOutline" />
        <h1>无法打开个人工坊</h1>
        <p>{{ error }}</p>
        <IonButton fill="outline" @click="load">
          重试
        </IonButton>
      </div>

      <template v-else-if="view">
        <section class="workshop-masthead">
          <div class="workshop-owner">
            <UserAvatar
              :src="view.workshop.ownerAvatar"
              :alt="view.workshop.ownerName"
              telemetry-surface="workshop.public"
              class="workshop-avatar"
            >
              <template #fallback>
                <div class="workshop-avatar workshop-avatar--fallback">
                  {{ view.workshop.ownerName.slice(0, 1) }}
                </div>
              </template>
            </UserAvatar>
            <div class="workshop-owner-copy">
              <span>坊主</span>
              <strong>{{ view.workshop.ownerName }}</strong>
            </div>
          </div>
          <h1>{{ view.workshop.name }}</h1>
          <p v-if="view.workshop.description">
            {{ view.workshop.description }}
          </p>

          <div v-if="view.workshop.status === 'disabled'" class="workshop-state workshop-state--disabled">
            个人工坊已停用，坊客作品暂不可见
          </div>
          <div v-else-if="view.access === 'pending'" class="workshop-state workshop-state--pending">
            加入申请等待坊主审批
          </div>
          <div v-else-if="view.access === 'blocked'" class="workshop-state workshop-state--disabled">
            当前账号无法申请加入
          </div>
          <div v-else-if="view.access === 'active' || view.access === 'owner'" class="workshop-state workshop-state--active">
            <IonIcon :icon="peopleOutline" />
            {{ view.access === 'owner' ? '坊主视图' : '已加入个人工坊' }}
          </div>
          <IonButton
            v-else-if="canRequest"
            :disabled="acting"
            class="join-button"
            @click="handleJoin"
          >
            <IonSpinner v-if="acting" name="crescent" />
            <IonIcon v-else slot="start" :icon="logInOutline" />
            {{ view.workshop.joinPolicy === 'open' ? '直接加入' : '申请加入' }}
          </IonButton>
          <div v-else-if="view.workshop.joinPolicy === 'closed'" class="workshop-state">
            个人工坊暂不接受新坊客
          </div>
        </section>

        <section v-if="view.access === 'active' || view.access === 'owner'" class="workshop-apps">
          <div class="workshop-section-heading">
            <div>
              <span>作品</span>
              <h2>工坊 App</h2>
            </div>
            <IonNote>{{ view.apps.length }} 个</IonNote>
          </div>

          <IonList v-if="view.apps.length" inset>
            <IonItem
              v-for="app in view.apps"
              :key="app._id"
              button
              :detail="false"
              @click="openApp(app)"
            >
              <AppIconBox
                slot="start"
                :icon="app.logo"
                :emoji="app.emoji"
                :color="app.themeColor"
                size="list"
              />
              <IonLabel>
                <h2>{{ app.name }}</h2>
                <p>{{ app.description || app.category || '应用' }}</p>
              </IonLabel>
              <IonNote v-if="app.audience === 'workshop'" slot="end">
                坊客专属
              </IonNote>
              <IonIcon slot="end" :icon="chevronForwardOutline" color="medium" />
            </IonItem>
          </IonList>
          <div v-else class="workshop-empty">
            坊主还没有发布工坊作品
          </div>

          <IonButton
            v-if="view.access === 'active'"
            fill="clear"
            color="medium"
            :disabled="acting"
            class="leave-button"
            @click="handleLeave"
          >
            <IonIcon slot="start" :icon="logOutOutline" />
            退出个人工坊
          </IonButton>
        </section>
      </template>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.workshop-content {
  --background: var(--ion-background-color);
}

.workshop-loading,
.workshop-message {
  min-height: 60vh;
  padding: 80px 28px 32px;
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  justify-content: center;
  gap: 12px;
}

.workshop-message ion-icon {
  font-size: 36px;
  color: var(--ion-color-medium);
}

.workshop-message h1,
.workshop-message p {
  margin: 0;
}

.workshop-message p {
  color: var(--ion-color-medium);
}

.workshop-masthead {
  position: relative;
  padding: 28px 24px 32px;
  overflow: hidden;
  background: var(--ion-item-background);
  border-bottom: 1px solid var(--ion-item-border-color);
}

.workshop-masthead::after {
  content: '';
  position: absolute;
  right: -40px;
  top: -24px;
  width: 132px;
  height: 72px;
  transform: rotate(-14deg);
  background: var(--ion-color-primary);
  opacity: 0.12;
}

.workshop-owner {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 26px;
}

.workshop-avatar {
  width: 48px;
  height: 48px;
  border-radius: 16px;
  object-fit: cover;
}

.workshop-avatar--fallback {
  display: grid;
  place-items: center;
  color: #fff;
  background: var(--ion-color-primary);
  font-size: 20px;
  font-weight: 700;
}

.workshop-owner-copy {
  display: flex;
  flex-direction: column;
}

.workshop-owner-copy span,
.workshop-section-heading span {
  color: var(--ion-color-medium);
  font-size: 11px;
  letter-spacing: 0.12em;
  text-transform: uppercase;
}

.workshop-masthead h1 {
  max-width: 520px;
  margin: 0;
  font-size: clamp(28px, 8vw, 42px);
  line-height: 1.05;
}

.workshop-masthead > p {
  max-width: 580px;
  margin: 14px 0 0;
  color: var(--ion-color-medium);
  line-height: 1.55;
}

.workshop-state {
  width: fit-content;
  margin-top: 24px;
  padding: 9px 12px;
  border-radius: 10px;
  color: var(--ion-color-medium-shade);
  background: var(--ylf-fill-secondary);
  font-size: 14px;
}

.workshop-state--active {
  display: flex;
  align-items: center;
  gap: 6px;
  color: var(--ion-color-success-shade);
}

.workshop-state--pending {
  color: var(--ion-color-warning-shade);
}

.workshop-state--disabled {
  color: var(--ion-color-danger-shade);
}

.join-button {
  margin-top: 24px;
  --border-radius: 12px;
}

.workshop-apps {
  padding: 28px 0 44px;
}

.workshop-section-heading {
  padding: 0 24px 8px;
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
}

.workshop-section-heading h2 {
  margin: 3px 0 0;
  font-size: 22px;
}

.workshop-empty {
  margin: 12px 24px;
  padding: 24px 0;
  color: var(--ion-color-medium);
  border-top: 1px solid var(--ion-item-border-color);
}

.leave-button {
  margin: 20px 16px 0;
}
</style>
