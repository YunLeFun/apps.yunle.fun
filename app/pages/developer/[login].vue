<script setup lang="ts">
import type { YlfAppInfo } from '@yunlefun/types'
import {
  IonBackButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonPage,
  IonSpinner,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { chevronForward, logoGithub } from 'ionicons/icons'

const route = useRoute()
const router = useRouter()

// Ionic + Nuxt 路由下 route.params 偶发为空，回退解析 URL（与 app/[id].vue 同款兜底）
function resolveLoginFromUrl(): string {
  if (!import.meta.client)
    return ''
  const match = window.location.pathname.match(/\/developer\/([^/]+)/)?.[1]
  return match ? decodeURIComponent(match) : ''
}

const login = computed(() => {
  const raw = route.params.login
  const val = Array.isArray(raw) ? raw[0] : raw
  if (val)
    return decodeURIComponent(val)
  return resolveLoginFromUrl()
})

// 个人市场独立于公共市场审核，读取坊主当前发布的公开作品。
const { apps, loading: catalogLoading, load } = usePersonalMarket(login)

// GitHub 公开资料（中文名 / 头像 / 简介）
const { profile } = useGithubProfile(login)

// 展示名优先级：应用记录 developerName > GitHub name > 登录名
const displayName = computed(() =>
  apps.value.find(a => a.developerName)?.developerName || profile.value?.name || login.value,
)
const bio = computed(() => profile.value?.bio || '')

// 头像：GitHub 资料头像 → github.com/{login}.png → 首字母
const avatarError = ref(false)
const avatarUrl = computed(() =>
  profile.value?.avatarUrl || (login.value ? `https://github.com/${encodeURIComponent(login.value)}.png?size=200` : ''),
)
const initial = computed(() => (displayName.value[0] || '?').toUpperCase())

watch([login, avatarUrl], () => {
  avatarError.value = false
})

function openAppDetail(app: Pick<YlfAppInfo, 'id' | 'slug'>) {
  router.push(`/app/${app.slug || app.id}`)
}

function openGithubProfile() {
  const url = profile.value?.htmlUrl || (login.value ? `https://github.com/${login.value}` : '')
  if (url)
    openInAppBrowser(url)
}

onMounted(load)
watch(login, load)
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/apps" text="" />
        </IonButtons>
        <IonTitle>个人市场</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true" class="developer-content">
      <div class="developer-container">
        <!-- 开发者信息卡 -->
        <div class="developer-hero">
          <div class="developer-hero-top">
            <div class="developer-avatar" :class="{ 'is-fallback': avatarError || !avatarUrl }">
              <img
                v-if="avatarUrl && !avatarError"
                :src="avatarUrl"
                :alt="displayName"
                referrerpolicy="no-referrer"
                @error="avatarError = true"
              >
              <span v-else>{{ initial }}</span>
            </div>
            <div class="developer-meta">
              <h1 class="developer-name">
                {{ displayName }}
              </h1>
              <p v-if="displayName !== login" class="developer-handle">
                @{{ login }}
              </p>
              <p class="developer-sub">
                {{ apps.length }} 个应用
              </p>
            </div>
          </div>
          <p v-if="bio" class="developer-bio">
            {{ bio }}
          </p>
        </div>

        <!-- GitHub 主页入口 -->
        <button type="button" class="developer-github" @click="openGithubProfile">
          <IonIcon :icon="logoGithub" class="gh-logo" />
          <span class="gh-text">在 GitHub 上查看</span>
          <IonIcon :icon="chevronForward" class="gh-chevron" />
        </button>

        <!-- 应用列表 -->
        <div class="developer-section">
          <h2 class="developer-section-title">
            应用
          </h2>

          <div v-if="catalogLoading && !apps.length" class="developer-loading">
            <IonSpinner name="crescent" />
          </div>

          <div v-else-if="apps.length" class="developer-app-list">
            <button
              v-for="(app, i) in apps"
              :key="app.id"
              type="button"
              class="dev-app-item"
              :class="{ 'dev-app-item--last': i === apps.length - 1 }"
              @click="openAppDetail(app)"
            >
              <AppIconBox
                class="flex-shrink-0"
                :icon="app.logo"
                :emoji="app.emoji"
                :color="app.themeColor"
                size="md"
              />
              <div class="dev-app-info">
                <div class="dev-app-name">
                  {{ app.name }}
                </div>
                <div class="dev-app-desc">
                  {{ app.description || app.category || '应用' }}
                </div>
              </div>
              <IonIcon :icon="chevronForward" class="dev-app-chevron" />
            </button>
          </div>

          <div v-else class="developer-empty">
            <div class="developer-empty-icon">
              📦
            </div>
            <p class="developer-empty-text">
              该开发者暂无公开应用
            </p>
          </div>
        </div>
      </div>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.developer-content {
  --background: var(--ion-background-color);
}

.developer-container {
  max-width: 980px;
  margin: 0 auto;
  padding-bottom: 40px;
}

/* 开发者信息卡 */
.developer-hero {
  display: flex;
  flex-direction: column;
  gap: 14px;
  padding: 24px 20px 20px;
  background: var(--ion-item-background);
}

.developer-hero-top {
  display: flex;
  align-items: center;
  gap: 16px;
}

.developer-avatar {
  width: 76px;
  height: 76px;
  border-radius: 50%;
  flex-shrink: 0;
  overflow: hidden;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--ylf-fill-secondary);
  box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.08);
}

.developer-avatar img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.developer-avatar.is-fallback {
  background: var(--ion-color-primary);
  color: #fff;
  font-size: 32px;
  font-weight: 600;
}

.developer-meta {
  min-width: 0;
  flex: 1;
}

.developer-name {
  margin: 0;
  font-size: 24px;
  font-weight: 700;
  line-height: 1.2;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.developer-handle {
  margin: 3px 0 0;
  font-size: 14px;
  color: var(--ion-color-medium);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.developer-sub {
  margin: 3px 0 0;
  font-size: 13px;
  color: var(--ylf-label-tertiary);
}

.developer-bio {
  margin: 0;
  font-size: 14px;
  line-height: 1.5;
  color: var(--ion-text-color);
}

/* GitHub 入口 */
.developer-github {
  appearance: none;
  -webkit-appearance: none;
  width: 100%;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 14px 20px;
  margin-top: 8px;
  border: 0;
  background: var(--ion-item-background);
  color: var(--ion-text-color);
  font-size: 15px;
  text-align: left;
  cursor: pointer;
}

.developer-github:active {
  background: var(--ylf-fill-secondary);
}

.gh-logo {
  font-size: 20px;
  flex-shrink: 0;
}

.gh-text {
  flex: 1;
}

.gh-chevron {
  font-size: 15px;
  color: var(--ylf-label-tertiary);
}

/* 应用列表区块 */
.developer-section {
  background: var(--ion-item-background);
  padding: 16px 20px 8px;
  margin-top: 8px;
}

.developer-section-title {
  margin: 0 0 4px;
  font-size: 20px;
  font-weight: 700;
}

.developer-loading {
  display: flex;
  justify-content: center;
  padding: 32px 0;
}

.developer-app-list {
  display: flex;
  flex-direction: column;
}

.dev-app-item {
  appearance: none;
  -webkit-appearance: none;
  width: 100%;
  position: relative;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 0;
  border: 0;
  background: none;
  text-align: left;
  cursor: pointer;
}

.dev-app-item:not(.dev-app-item--last)::after {
  content: '';
  position: absolute;
  bottom: 0;
  left: 76px;
  right: 0;
  height: 0.5px;
  background: var(--ylf-separator);
}

.dev-app-item:active {
  opacity: 0.6;
}

.dev-app-info {
  min-width: 0;
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.dev-app-name {
  font-size: 16px;
  font-weight: 500;
  color: var(--ion-text-color);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.dev-app-desc {
  font-size: 13px;
  color: var(--ion-color-medium);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.dev-app-chevron {
  font-size: 16px;
  flex-shrink: 0;
  color: var(--ylf-label-tertiary);
}

/* 空状态 */
.developer-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  padding: 40px 0;
  text-align: center;
}

.developer-empty-icon {
  font-size: 40px;
  opacity: 0.4;
}

.developer-empty-text {
  margin: 0;
  font-size: 15px;
  color: var(--ion-color-medium);
}
</style>
