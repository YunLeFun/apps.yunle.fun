<script setup lang="ts">
import type { WorkshopPublicInfo } from '~/types/workshop'
import {
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonModal,
  IonSearchbar,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import {
  addCircleOutline,
  albumsOutline,
  checkmarkCircle,
  close,
  globeOutline,
  lockClosed,
  logInOutline,
  qrCodeOutline,
  settingsOutline,
} from 'ionicons/icons'

const props = defineProps<{
  isOpen: boolean
  currentScope: string
  workshops: WorkshopPublicInfo[]
  isLoggedIn: boolean
  ownedWorkshopId?: string
  loading?: boolean
}>()

const emit = defineEmits<{
  close: []
  select: [scope: string]
  scan: []
  manage: []
  login: []
}>()

const query = ref('')

const visibleWorkshops = computed(() => {
  const keyword = query.value.trim().toLocaleLowerCase()
  if (!keyword)
    return props.workshops

  return props.workshops.filter(workshop =>
    workshop.name.toLocaleLowerCase().includes(keyword)
    || workshop.ownerName.toLocaleLowerCase().includes(keyword)
    || workshop.description?.toLocaleLowerCase().includes(keyword),
  )
})

const joinedCount = computed(() =>
  props.workshops.filter(workshop => workshop._id !== props.ownedWorkshopId).length,
)

watch(() => props.isOpen, (open) => {
  if (open)
    query.value = ''
})

function select(scope: string) {
  emit('select', scope)
  emit('close')
}

function scan() {
  emit('close')
  emit('scan')
}

function manage() {
  emit('close')
  emit('manage')
}

function login() {
  emit('close')
  emit('login')
}
</script>

<template>
  <IonModal
    class="workshop-picker"
    :is-open="isOpen"
    :breakpoints="[0, 0.72, 0.94]"
    :initial-breakpoint="0.72"
    handle-behavior="cycle"
    @did-dismiss="emit('close')"
  >
    <IonHeader class="ion-no-border">
      <IonToolbar>
        <IonTitle>切换工坊</IonTitle>
        <IonButtons slot="end">
          <IonButton aria-label="关闭" @click="emit('close')">
            <IonIcon slot="icon-only" :icon="close" />
          </IonButton>
        </IonButtons>
      </IonToolbar>
      <IonToolbar v-if="isLoggedIn" class="picker-search-toolbar">
        <IonSearchbar
          v-model="query"
          mode="ios"
          aria-label="搜索工坊"
          placeholder="搜索工坊名称或坊主"
          :debounce="120"
          :disabled="loading"
          class="picker-search"
        />
      </IonToolbar>
    </IonHeader>

    <IonContent>
      <div class="picker-content">
        <section v-if="workshops.length" class="scope-section">
          <p class="section-label">
            浏览范围
          </p>
          <button
            type="button"
            class="scope-row"
            :class="{ 'scope-row--active': currentScope === 'all' }"
            @click="select('all')"
          >
            <span class="scope-icon scope-icon--all">
              <IonIcon :icon="albumsOutline" />
            </span>
            <span class="scope-copy">
              <strong>全部动态</strong>
              <small>云乐坊与 {{ workshops.length }} 个个人工坊</small>
            </span>
            <IonIcon
              v-if="currentScope === 'all'"
              class="scope-check"
              :icon="checkmarkCircle"
            />
          </button>
        </section>

        <section class="scope-section">
          <p class="section-label">
            公开浏览
          </p>
          <button
            type="button"
            class="scope-row"
            :class="{ 'scope-row--active': currentScope === 'public' }"
            @click="select('public')"
          >
            <span class="scope-icon scope-icon--public">
              <IonIcon :icon="globeOutline" />
            </span>
            <span class="scope-copy">
              <strong>云乐坊</strong>
              <small>所有人都可以浏览</small>
            </span>
            <IonIcon
              v-if="currentScope === 'public'"
              class="scope-check"
              :icon="checkmarkCircle"
            />
          </button>
        </section>

        <section class="scope-section scope-section--private">
          <p class="section-label">
            个人工坊
            <span v-if="!loading">{{ joinedCount ? `已加入 ${joinedCount} 个` : '' }}</span>
          </p>

          <div v-if="loading" class="picker-loading" aria-label="正在加载工坊">
            <span v-for="index in 2" :key="index" class="picker-skeleton" />
          </div>

          <template v-else-if="visibleWorkshops.length">
            <button
              v-for="workshop in visibleWorkshops"
              :key="workshop._id"
              type="button"
              class="scope-row"
              :class="{ 'scope-row--active': currentScope === workshop._id }"
              @click="select(workshop._id)"
            >
              <span class="scope-avatar">
                <img
                  v-if="workshop.ownerAvatar"
                  :src="workshop.ownerAvatar"
                  alt=""
                >
                <span v-else>{{ workshop.name.slice(0, 1) }}</span>
                <IonIcon class="scope-lock" :icon="lockClosed" />
              </span>
              <span class="scope-copy">
                <strong>{{ workshop.name }}</strong>
                <small>
                  {{ workshop._id === ownedWorkshopId ? '我创建的' : `${workshop.ownerName}的工坊` }}
                </small>
              </span>
              <IonIcon
                v-if="currentScope === workshop._id"
                class="scope-check"
                :icon="checkmarkCircle"
              />
            </button>
          </template>

          <div v-else class="private-empty">
            <strong>
              {{ query
                ? '没有匹配的工坊'
                : isLoggedIn
                  ? '还没有加入个人工坊'
                  : '登录后查看个人工坊' }}
            </strong>
            <span>
              {{ query
                ? '换个名称或坊主试试'
                : isLoggedIn
                  ? '扫描坊主分享的二维码即可申请加入'
                  : '登录当前账号后，会同步显示已加入的工坊' }}
            </span>
          </div>
        </section>

        <div class="picker-actions">
          <button
            type="button"
            class="picker-action picker-action--primary"
            @click="isLoggedIn ? scan() : login()"
          >
            <IonIcon :icon="isLoggedIn ? qrCodeOutline : logInOutline" />
            {{ isLoggedIn ? '扫码加入' : '登录查看' }}
          </button>
          <button
            type="button"
            class="picker-action"
            @click="isLoggedIn ? manage() : scan()"
          >
            <IonIcon :icon="isLoggedIn ? (ownedWorkshopId ? settingsOutline : addCircleOutline) : qrCodeOutline" />
            {{ isLoggedIn ? (ownedWorkshopId ? '管理工坊' : '开启工坊') : '扫码加入' }}
          </button>
        </div>
      </div>
    </IonContent>
  </IonModal>
</template>

<style scoped>
.workshop-picker {
  --border-radius: 24px 24px 0 0;
  --box-shadow: 0 -18px 48px rgba(0, 0, 0, 0.16);
}

.picker-search-toolbar {
  --min-height: 48px;
}

.picker-search {
  --background: var(--ylf-fill-tertiary);
  --border-radius: 12px;
  --box-shadow: none;
  --placeholder-color: var(--ylf-label-secondary);
  padding: 2px 16px 8px;
}

.picker-content {
  padding: 8px 12px 28px;
}

.scope-section {
  margin-bottom: 18px;
}

.section-label {
  display: flex;
  justify-content: space-between;
  margin: 0;
  padding: 0 8px 6px;
  color: var(--ylf-label-secondary);
  font-size: 12px;
  font-weight: 600;
}

.section-label span {
  font-weight: 400;
}

.scope-row {
  position: relative;
  width: 100%;
  min-height: 62px;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 12px;
  border: 0;
  border-radius: 14px;
  color: var(--ion-text-color);
  background: transparent;
  text-align: start;
  -webkit-tap-highlight-color: transparent;
}

.scope-row::after {
  content: '';
  position: absolute;
  right: 12px;
  bottom: 0;
  left: 66px;
  height: 0.5px;
  background: var(--ylf-separator);
  opacity: 0.35;
}

.scope-row:last-child::after {
  display: none;
}

.scope-row:active {
  background: var(--ylf-fill-tertiary);
}

.scope-row--active {
  background: color-mix(in srgb, var(--ion-color-primary) 9%, transparent);
}

.scope-icon,
.scope-avatar {
  position: relative;
  width: 42px;
  height: 42px;
  flex: 0 0 42px;
  display: grid;
  place-items: center;
  overflow: visible;
  border-radius: 13px;
  color: #fff;
  font-size: 22px;
  font-weight: 700;
}

.scope-icon--all {
  background: linear-gradient(145deg, var(--ylf-color-indigo), var(--ylf-color-purple));
}

.scope-icon--public {
  background: linear-gradient(145deg, var(--ion-color-primary), var(--ylf-color-cyan));
}

.scope-avatar {
  background: linear-gradient(145deg, var(--ylf-color-indigo), var(--ylf-color-purple));
}

.scope-avatar img,
.scope-avatar > span {
  width: 100%;
  height: 100%;
  display: grid;
  place-items: center;
  border-radius: inherit;
  object-fit: cover;
}

.scope-lock {
  position: absolute;
  right: -5px;
  bottom: -4px;
  width: 17px;
  height: 17px;
  padding: 3px;
  border: 2px solid var(--ion-background-color);
  border-radius: 50%;
  color: #fff;
  background: var(--ylf-color-indigo);
  font-size: 11px;
}

.scope-copy {
  min-width: 0;
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 3px;
}

.scope-copy strong,
.scope-copy small {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.scope-copy strong {
  font-size: 16px;
  font-weight: 600;
}

.scope-copy small {
  color: var(--ylf-label-secondary);
  font-size: 13px;
}

.scope-check {
  flex: 0 0 auto;
  color: var(--ion-color-primary);
  font-size: 23px;
}

.private-empty {
  min-height: 94px;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 5px;
  margin: 0 4px;
  padding: 18px;
  border: 1px dashed var(--ylf-separator);
  border-radius: 14px;
  color: var(--ylf-label-secondary);
  text-align: center;
}

.private-empty strong {
  color: var(--ion-text-color);
  font-size: 14px;
}

.private-empty span {
  font-size: 12px;
  line-height: 1.45;
}

.picker-loading {
  display: grid;
  gap: 8px;
}

.picker-skeleton {
  height: 62px;
  border-radius: 14px;
  background: linear-gradient(
    100deg,
    var(--ylf-fill-tertiary) 20%,
    var(--ylf-fill-secondary) 38%,
    var(--ylf-fill-tertiary) 56%
  );
  background-size: 240% 100%;
  animation: picker-shimmer 1.2s linear infinite;
}

.picker-actions {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
  padding: 2px 4px calc(12px + var(--ion-safe-area-bottom));
}

.picker-action {
  min-height: 46px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 7px;
  border: 0;
  border-radius: 13px;
  color: var(--ion-color-primary);
  background: var(--ylf-fill-tertiary);
  font-size: 15px;
  font-weight: 600;
  -webkit-tap-highlight-color: transparent;
}

.picker-action--primary {
  color: #fff;
  background: var(--ion-color-primary);
}

.picker-action:active {
  opacity: 0.72;
  transform: scale(0.98);
}

@keyframes picker-shimmer {
  to {
    background-position-x: -240%;
  }
}

@media (min-width: 768px) {
  .workshop-picker {
    --width: 440px;
    --height: min(680px, 84vh);
    --border-radius: 22px;
  }
}

@media (prefers-reduced-motion: reduce) {
  .picker-skeleton {
    animation: none;
  }

  .picker-action:active {
    transform: none;
  }
}
</style>
