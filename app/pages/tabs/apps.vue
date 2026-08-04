<script setup lang="ts">
import type { YlfAppInfo } from '@yunlefun/types'
import type { WorkshopScopedApp } from '~/components/workshop/AppList.vue'
import type { WorkshopPublicInfo, WorkshopView } from '~/types/workshop'
import {
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonLabel,
  IonPage,
  IonSearchbar,
  IonSegment,
  IonSegmentButton,
  IonToolbar,
  onIonViewWillEnter,
} from '@ionic/vue'
import {
  albumsOutline,
  chevronDown,
  globeOutline,
  lockClosed,
  qrCodeOutline,
  refreshOutline,
} from 'ionicons/icons'
import { getAvailableAppCategories } from '~/utils/appCategories'
import { recordToAppInfo } from '~/utils/appRecord'

const {
  searchQuery,
  selectedCategory,
  categories: publicCategories,
  changeCategory,
  debouncedSearch,
  queryApps,
} = useWorkshop()

const SCOPE_STORAGE_KEY = 'ylf:workshop-scope:v1'

const router = useRouter()
const userStore = useUserStore()
const workshopModule = usePersonalWorkshop()
const { catalog } = useAppCatalog()
const { navigateToScan } = useScanBridge()
const { handleScanResult } = useWorkshopScan()

const pickerOpen = ref(false)
const workshopListLoading = ref(false)
const joinedWorkshops = ref<WorkshopPublicInfo[]>([])
const ownedWorkshop = ref<WorkshopPublicInfo | null>(null)
const workshopViews = ref<Record<string, WorkshopView>>({})
const workshopViewLoading = ref<Record<string, boolean>>({})
const workshopViewErrors = ref<Record<string, string>>({})
const selectedScope = useState<string>('workshop:selected-scope', () => 'public')

const availableWorkshops = computed(() => {
  const workshops = ownedWorkshop.value
    ? [ownedWorkshop.value, ...joinedWorkshops.value]
    : [...joinedWorkshops.value]
  const seen = new Set<string>()
  return workshops.filter((workshop) => {
    if (seen.has(workshop._id))
      return false
    seen.add(workshop._id)
    return true
  })
})

const currentWorkshop = computed(() =>
  availableWorkshops.value.find(workshop => workshop._id === selectedScope.value),
)
const currentView = computed(() =>
  selectedScope.value === 'public' || selectedScope.value === 'all'
    ? null
    : workshopViews.value[selectedScope.value],
)
const isPublicScope = computed(() => selectedScope.value === 'public')
const isAllScope = computed(() => selectedScope.value === 'all')
const isPrivateScope = computed(() => !isPublicScope.value && !isAllScope.value)

const scopeTitle = computed(() => {
  if (isAllScope.value)
    return '全部动态'
  return currentWorkshop.value?.name || '云乐坊'
})
const scopeLabel = computed(() => {
  if (isAllScope.value)
    return `${availableWorkshops.value.length + 1} 个工坊`
  return isPrivateScope.value ? '个人工坊' : '公开作品'
})
const scopeIcon = computed(() => {
  if (isAllScope.value)
    return albumsOutline
  return isPrivateScope.value ? lockClosed : globeOutline
})
const searchPlaceholder = computed(() =>
  isAllScope.value
    ? '搜索全部工坊中的应用'
    : `搜索${scopeTitle.value}中的应用`,
)

const scopedCategoryApps = computed(() => {
  if (isPrivateScope.value)
    return currentView.value?.apps ?? []

  const apps: Array<{ category?: string }> = [...catalog.value]
  for (const workshop of availableWorkshops.value) {
    const view = workshopViews.value[workshop._id]
    if (view)
      apps.push(...view.apps)
  }
  return apps
})

const categories = computed(() =>
  isPublicScope.value
    ? publicCategories.value
    : getAvailableAppCategories(scopedCategoryApps.value),
)

function matchesCurrentFilters(app: YlfAppInfo) {
  if (
    selectedCategory.value !== '全部'
    && app.category?.trim() !== selectedCategory.value
  ) {
    return false
  }

  const keyword = searchQuery.value.trim().toLocaleLowerCase()
  if (!keyword)
    return true

  return app.name.toLocaleLowerCase().includes(keyword)
    || app.description?.toLocaleLowerCase().includes(keyword)
    || app.category?.toLocaleLowerCase().includes(keyword)
}

const privateScopeItems = computed<WorkshopScopedApp[]>(() => {
  if (!currentView.value)
    return []

  return currentView.value.apps
    .map((record) => {
      const app = recordToAppInfo(record)
      return {
        key: `${currentView.value!.workshop._id}:${app.id}`,
        app,
        private: record.audience === 'workshop',
      }
    })
    .filter(item => matchesCurrentFilters(item.app))
})

const allScopeItems = computed<WorkshopScopedApp[]>(() => {
  const items = new Map<string, WorkshopScopedApp>()

  for (const app of catalog.value) {
    items.set(app.id, {
      key: `public:${app.id}`,
      app,
      private: false,
      sourceName: '云乐坊',
    })
  }

  for (const workshop of availableWorkshops.value) {
    const view = workshopViews.value[workshop._id]
    if (!view)
      continue
    for (const record of view.apps) {
      if (items.has(record._id))
        continue
      const app = recordToAppInfo(record)
      items.set(app.id, {
        key: `${workshop._id}:${app.id}`,
        app,
        private: record.audience === 'workshop',
        sourceName: workshop.name,
      })
    }
  }

  return Array.from(items.values()).filter(item => matchesCurrentFilters(item.app))
})

const scopeLoading = computed(() => {
  if (isAllScope.value) {
    return availableWorkshops.value.some(workshop =>
      workshopViewLoading.value[workshop._id],
    )
  }
  return isPrivateScope.value && workshopViewLoading.value[selectedScope.value]
})

const scopeError = computed(() =>
  isPrivateScope.value ? workshopViewErrors.value[selectedScope.value] : '',
)

function startScanFlow() {
  navigateToScan(handleScanResult)
}

async function loadAvailableWorkshops() {
  if (!userStore.isLoggedIn) {
    joinedWorkshops.value = []
    ownedWorkshop.value = null
    if (selectedScope.value !== 'public') {
      selectedScope.value = 'public'
      persistScope('public')
    }
    return
  }
  if (workshopListLoading.value)
    return

  workshopListLoading.value = true
  try {
    const [joined, management] = await Promise.all([
      workshopModule.getJoined(),
      workshopModule.getManagement(),
    ])
    joinedWorkshops.value = joined.filter(workshop => workshop.status === 'active')
    ownedWorkshop.value = management?.workshop.status === 'active'
      ? management.workshop
      : null

    const validScopes = new Set([
      'public',
      ...(availableWorkshops.value.length ? ['all'] : []),
      ...availableWorkshops.value.map(workshop => workshop._id),
    ])
    if (!validScopes.has(selectedScope.value))
      await selectScope('public')
    else if (selectedScope.value !== 'public')
      await loadSelectedScope()
  }
  catch {
    joinedWorkshops.value = []
    ownedWorkshop.value = null
    if (selectedScope.value !== 'public') {
      selectedScope.value = 'public'
      persistScope('public')
    }
  }
  finally {
    workshopListLoading.value = false
  }
}

async function ensureWorkshopView(workshopId: string, force = false) {
  if (!force && workshopViews.value[workshopId])
    return

  workshopViewLoading.value = {
    ...workshopViewLoading.value,
    [workshopId]: true,
  }
  workshopViewErrors.value = {
    ...workshopViewErrors.value,
    [workshopId]: '',
  }
  try {
    const view = await workshopModule.getView(workshopId)
    workshopViews.value = {
      ...workshopViews.value,
      [workshopId]: view,
    }
  }
  catch (reason: unknown) {
    workshopViewErrors.value = {
      ...workshopViewErrors.value,
      [workshopId]: reason instanceof Error ? reason.message : '工坊加载失败',
    }
  }
  finally {
    workshopViewLoading.value = {
      ...workshopViewLoading.value,
      [workshopId]: false,
    }
  }
}

async function loadSelectedScope(force = false) {
  if (isPublicScope.value) {
    await queryApps(true)
    return
  }

  if (isAllScope.value) {
    const queue = [...availableWorkshops.value]
    const workerCount = Math.min(4, queue.length)
    await Promise.all(Array.from({ length: workerCount }, async () => {
      while (queue.length) {
        const workshop = queue.shift()
        if (workshop)
          await ensureWorkshopView(workshop._id, force)
      }
    }))
    return
  }

  await ensureWorkshopView(selectedScope.value, force)
}

function persistScope(scope: string) {
  if (import.meta.client) {
    try {
      localStorage.setItem(SCOPE_STORAGE_KEY, scope)
    }
    catch {}
  }
}

async function selectScope(scope: string) {
  selectedScope.value = scope
  persistScope(scope)
  await loadSelectedScope()
}

async function retryCurrentScope() {
  await loadSelectedScope(true)
}

function manageWorkshops() {
  router.push('/user/workshop')
}

function openScopedApp(item: WorkshopScopedApp) {
  if (item.private && item.app.websiteUrl) {
    openCatalogAppInBrowser(item.app)
    return
  }
  router.push(`/app/${item.app.slug || item.app.id}`)
}

onMounted(async () => {
  if (import.meta.client) {
    try {
      selectedScope.value = localStorage.getItem(SCOPE_STORAGE_KEY) || 'public'
    }
    catch {}
  }
  await Promise.all([
    queryApps(true),
    loadAvailableWorkshops(),
  ])
})

onIonViewWillEnter(() => {
  if (userStore.isLoggedIn)
    loadAvailableWorkshops()
})

watch(() => userStore.isLoggedIn, (loggedIn) => {
  if (loggedIn)
    loadAvailableWorkshops()
  else
    selectScope('public')
})

watch(categories, (availableCategories) => {
  const selectedCategoryStillExists = availableCategories.some(
    category => category.name === selectedCategory.value,
  )
  if (selectedCategoryStillExists)
    return

  if (isPublicScope.value)
    changeCategory('全部')
  else
    selectedCategory.value = '全部'
}, { flush: 'sync' })

function handleSegmentChange(event: CustomEvent) {
  if (isPublicScope.value)
    changeCategory(event.detail.value)
  else
    selectedCategory.value = event.detail.value
}

function handleSearchInput() {
  if (isPublicScope.value)
    debouncedSearch()
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar class="scope-toolbar">
        <IonButtons slot="start" class="scope-buttons">
          <button
            type="button"
            class="scope-trigger"
            aria-haspopup="dialog"
            :aria-expanded="pickerOpen"
            aria-label="切换工坊"
            @click="pickerOpen = true"
          >
            <span class="scope-trigger-icon">
              <IonIcon :icon="scopeIcon" />
            </span>
            <span class="scope-trigger-copy">
              <strong>{{ scopeTitle }}</strong>
              <small>{{ scopeLabel }}</small>
            </span>
            <IonIcon class="scope-trigger-chevron" :icon="chevronDown" />
          </button>
        </IonButtons>
        <IonButtons slot="end">
          <IonButton aria-label="扫码加入个人工坊" @click="startScanFlow">
            <IonIcon slot="icon-only" :icon="qrCodeOutline" />
          </IonButton>
        </IonButtons>
      </IonToolbar>

      <IonToolbar>
        <IonSearchbar
          v-model="searchQuery"
          aria-label="搜索应用"
          :placeholder="searchPlaceholder"
          :animated="true"
          show-cancel-button="focus"
          class="app-store-searchbar"
          mode="ios"
          @ion-input="handleSearchInput"
          @ion-clear="handleSearchInput"
        />
      </IonToolbar>

      <IonToolbar>
        <IonSegment
          :value="selectedCategory"
          scrollable
          mode="ios"
          @ion-change="handleSegmentChange"
        >
          <IonSegmentButton
            v-for="category in categories"
            :key="category.id"
            :value="category.name"
          >
            <IonLabel>{{ category.name }}</IonLabel>
          </IonSegmentButton>
        </IonSegment>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <div class="content-wrapper">
        <AppList v-if="isPublicScope" />

        <template v-else>
          <section v-if="isAllScope" class="scope-context scope-context--all">
            <span class="context-mark">
              <IonIcon :icon="albumsOutline" />
            </span>
            <div>
              <strong>全部动态</strong>
              <p>聚合云乐坊和你可访问的个人工坊，重复应用只显示一次。</p>
            </div>
          </section>

          <section v-else-if="currentWorkshop" class="scope-context scope-context--private">
            <span class="context-avatar">
              <img
                v-if="currentWorkshop.ownerAvatar"
                :src="currentWorkshop.ownerAvatar"
                alt=""
              >
              <span v-else>{{ currentWorkshop.name.slice(0, 1) }}</span>
              <IonIcon :icon="lockClosed" />
            </span>
            <div class="context-copy">
              <strong>{{ currentWorkshop.name }}</strong>
              <p>
                {{ currentWorkshop.description || `${currentWorkshop.ownerName}的个人工坊` }}
              </p>
            </div>
            <span v-if="currentView" class="context-count">{{ currentView.apps.length }} 个</span>
          </section>

          <div v-if="scopeError" class="scope-error">
            <strong>暂时无法打开这个工坊</strong>
            <span>{{ scopeError }}</span>
            <IonButton fill="clear" size="small" @click="retryCurrentScope">
              <IonIcon slot="start" :icon="refreshOutline" />
              重试
            </IonButton>
          </div>

          <WorkshopAppList
            v-else
            :items="isAllScope ? allScopeItems : privateScopeItems"
            :loading="scopeLoading"
            :empty-title="searchQuery || selectedCategory !== '全部' ? '没有匹配的应用' : '这里还没有应用'"
            :empty-hint="searchQuery || selectedCategory !== '全部' ? '换个分类或关键词试试' : '坊主发布作品后会显示在这里'"
            @open="openScopedApp"
          />
        </template>
      </div>
    </IonContent>

    <WorkshopPickerSheet
      :is-open="pickerOpen"
      :current-scope="selectedScope"
      :workshops="availableWorkshops"
      :is-logged-in="userStore.isLoggedIn"
      :owned-workshop-id="ownedWorkshop?._id"
      :loading="workshopListLoading"
      @close="pickerOpen = false"
      @select="selectScope"
      @scan="startScanFlow"
      @manage="manageWorkshops"
      @login="router.push('/login')"
    />
  </IonPage>
</template>

<style scoped>
.scope-toolbar {
  --min-height: 58px;
}

.scope-buttons {
  max-width: min(62vw, 300px);
  margin-inline-start: 6px;
}

.scope-trigger {
  min-width: 0;
  max-width: 100%;
  min-height: 48px;
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 4px 8px;
  border: 0;
  border-radius: 12px;
  color: var(--ion-text-color);
  background: transparent;
  text-align: start;
  -webkit-tap-highlight-color: transparent;
}

.scope-trigger:active {
  background: var(--ylf-fill-tertiary);
}

.scope-trigger-icon {
  width: 32px;
  height: 32px;
  flex: 0 0 32px;
  display: grid;
  place-items: center;
  border-radius: 10px;
  color: #fff;
  background: linear-gradient(145deg, var(--ion-color-primary), var(--ylf-color-indigo));
  font-size: 17px;
}

.scope-trigger-copy {
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.scope-trigger-copy strong,
.scope-trigger-copy small {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.scope-trigger-copy strong {
  font-size: 17px;
  font-weight: 700;
  line-height: 1.15;
  letter-spacing: -0.015em;
}

.scope-trigger-copy small {
  color: var(--ylf-label-secondary);
  font-size: 10px;
  font-weight: 500;
  line-height: 1.2;
}

.scope-trigger-chevron {
  flex: 0 0 auto;
  color: var(--ylf-label-secondary);
  font-size: 14px;
}

/* ==================== 搜索栏 ==================== */
.app-store-searchbar {
  --background: var(--ylf-fill-tertiary);
  --border-radius: 10px;
  --box-shadow: none;
  --cancel-button-color: var(--ion-color-primary);
  --placeholder-color: var(--ylf-label-secondary);
  --icon-color: var(--ylf-label-secondary);
  --clear-button-color: var(--ylf-label-secondary);
  padding: 0 16px;
  font-size: 17px;
  font-weight: 400;
}

.app-store-searchbar::part(native) {
  height: 36px;
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
}

.app-store-searchbar::part(native):focus-within {
  --background: var(--ylf-fill-secondary);
}

/* ==================== Content 区域 ==================== */
.content-wrapper {
  padding: 0 16px 16px;
}

.scope-context {
  position: relative;
  min-height: 76px;
  display: flex;
  align-items: center;
  gap: 12px;
  margin: 10px 0 8px;
  padding: 12px 14px;
  overflow: hidden;
  border-radius: 18px;
}

.scope-context::after {
  content: '';
  position: absolute;
  right: -28px;
  top: -18px;
  width: 92px;
  height: 62px;
  border-radius: 50%;
  background: currentColor;
  opacity: 0.07;
}

.scope-context--all {
  color: var(--ylf-color-indigo);
  background: color-mix(in srgb, var(--ylf-color-indigo) 9%, var(--ion-item-background));
}

.scope-context--private {
  color: var(--ylf-color-purple);
  background: color-mix(in srgb, var(--ylf-color-purple) 8%, var(--ion-item-background));
}

.context-mark,
.context-avatar {
  position: relative;
  width: 46px;
  height: 46px;
  flex: 0 0 46px;
  display: grid;
  place-items: center;
  border-radius: 15px;
  color: #fff;
  background: linear-gradient(145deg, var(--ylf-color-indigo), var(--ylf-color-purple));
  font-size: 22px;
  font-weight: 700;
}

.context-avatar img,
.context-avatar > span {
  width: 100%;
  height: 100%;
  display: grid;
  place-items: center;
  border-radius: inherit;
  object-fit: cover;
}

.context-avatar ion-icon {
  position: absolute;
  right: -4px;
  bottom: -4px;
  width: 14px;
  height: 14px;
  padding: 3px;
  border: 2px solid var(--ion-item-background);
  border-radius: 50%;
  color: #fff;
  background: var(--ylf-color-indigo);
  font-size: 10px;
}

.scope-context > div,
.context-copy {
  min-width: 0;
  flex: 1;
}

.scope-context strong {
  display: block;
  overflow: hidden;
  color: var(--ion-text-color);
  font-size: 15px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.scope-context p {
  display: -webkit-box;
  overflow: hidden;
  margin: 3px 0 0;
  color: var(--ylf-label-secondary);
  font-size: 12px;
  line-height: 1.35;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
}

.context-count {
  flex: 0 0 auto;
  padding: 4px 7px;
  border-radius: 8px;
  color: var(--ylf-label-secondary);
  background: var(--ylf-fill-tertiary);
  font-size: 11px;
}

.scope-error {
  min-height: 260px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 6px;
  color: var(--ylf-label-secondary);
  text-align: center;
}

.scope-error strong {
  color: var(--ion-text-color);
}

.scope-error span {
  max-width: 280px;
  font-size: 13px;
}

/* ==================== 响应式设计 ==================== */
@media (min-width: 768px) {
  .scope-buttons {
    max-width: 360px;
  }

  .content-wrapper {
    max-width: 980px;
    margin: 0 auto;
    padding: 0 24px 24px;
  }
}

@media (min-width: 1024px) {
  .content-wrapper {
    max-width: 1200px;
    padding: 0 32px 32px;
  }
}

/* ==================== 无障碍优化 ==================== */
@media (prefers-reduced-motion: reduce) {
  .app-store-searchbar::part(native) {
    transition: none;
  }
}

/* Dark mode 不再需要单独覆盖 —— 所有颜色已经通过 CSS 变量
   在浅/深色之间自动切换（见 css-vars.css 与 Ionic 调色板） */
</style>
