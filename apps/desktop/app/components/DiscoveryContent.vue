<script setup lang="ts">
import type { CatalogEntry } from '../../shared/desktop'
import { COOK_FEATURE_IMAGE_URL, EDITORIAL_MEDIA_ORIGIN } from '../../shared/editorial-media'
import { filterCatalog, resolveFeatured } from '../utils/catalog-view'

const props = withDefaults(defineProps<{
  apps: readonly CatalogEntry[]
  view: 'explore' | 'all' | 'recent' | 'category'
  category?: string
  query?: string
  recentApps: readonly CatalogEntry[]
  available: boolean
  loading?: boolean
}>(), { category: '', query: '', loading: false })
defineEmits<{ open: [appId: string], navigate: [view: 'all'] }>()

const featureImageUrl = computed(() => EDITORIAL_MEDIA_ORIGIN ? COOK_FEATURE_IMAGE_URL : '')
const featureImageError = shallowRef(false)
const showFeatureImage = computed(() => !!featureImageUrl.value && !featureImageError.value)
watch(featureImageUrl, () => {
  featureImageError.value = false
})
const search = computed(() => props.query.trim().toLocaleLowerCase())
const explore = computed(() => props.view === 'explore' && !search.value)
const featuredApp = computed(() => props.apps.find(app => app.slug === 'cook' && app.available))
const dailyApps = computed(() => resolveFeatured(props.apps))
const otherApps = computed(() => {
  const featured = new Set(dailyApps.value.map(app => app.slug))
  if (featuredApp.value)
    featured.add(featuredApp.value.slug)
  return props.apps.filter(app => !featured.has(app.slug)).slice(0, 6)
})
const visibleApps = computed(() => {
  const apps = props.view === 'recent' ? props.recentApps : props.apps
  return filterCatalog(apps, { category: props.view === 'category' ? props.category : '', query: props.query })
})
const title = computed(() => {
  if (search.value)
    return '搜索结果'
  if (props.view === 'recent')
    return '最近打开'
  if (props.view === 'category')
    return props.category
  return props.view === 'all' ? '全部应用' : '探索'
})
const subtitle = computed(() => {
  if (search.value)
    return `找到 ${visibleApps.value.length} 个与“${props.query.trim()}”相关的应用`
  if (props.view === 'recent')
    return '继续探索你最近使用的应用'
  if (props.view === 'category')
    return `发现 ${visibleApps.value.length} 个${props.category}应用`
  return props.view === 'all' ? `每一个小应用，都有一点新意 · ${props.apps.length} 个应用` : '为日常找到一点新灵感'
})
const emptyTitle = computed(() => props.loading ? '正在更新应用目录' : props.view === 'recent' && !search.value ? '还没有最近打开的应用' : '没有找到应用')
const emptyDescription = computed(() => props.loading ? '稍等片刻，新的灵感马上到来。' : props.view === 'recent' && !search.value ? '打开一个应用后，你可以从这里继续。' : search.value ? '试试其他名称或关键词。' : '刷新目录，看看有没有新的发现。')
</script>

<template>
  <div class="discovery-content">
    <div class="discovery-inner">
      <header class="discovery-heading">
        <h1 class="page-title">
          {{ title }}
        </h1>
        <p class="page-subtitle">
          {{ subtitle }}
        </p>
      </header>

      <template v-if="explore">
        <section v-if="featuredApp" class="cook-feature" :class="{ 'has-feature-art': showFeatureImage }" aria-label="精选应用：今天来做菜">
          <img
            v-if="showFeatureImage" class="feature-art" :src="featureImageUrl"
            alt="" draggable="false" loading="lazy" referrerpolicy="no-referrer" @error="featureImageError = true"
          >
          <div class="feature-copy">
            <h2 class="feature-title">
              今天，吃点什么？
            </h2>
            <p class="feature-description">
              选好食材，让灵感上桌。
            </p>
            <button
              class="feature-button" :disabled="!available" aria-label="体验今天来做菜"
              @click="$emit('open', featuredApp.id)"
            >
              打开应用
            </button>
          </div>
        </section>

        <section v-if="dailyApps.length" class="collection-section" aria-labelledby="daily-apps-title">
          <div class="section-heading">
            <h2 id="daily-apps-title" class="section-title">
              日常小工具
            </h2>
            <button class="see-all" @click="$emit('navigate', 'all')">
              查看全部 <span aria-hidden="true">›</span>
            </button>
          </div>
          <AppCollection :apps="dailyApps" :available="available" @open="$emit('open', $event)" />
        </section>

        <section v-if="otherApps.length" class="collection-section" aria-labelledby="more-apps-title">
          <div class="section-heading">
            <h2 id="more-apps-title" class="section-title">
              所有应用
            </h2>
            <button v-if="!dailyApps.length" class="see-all" @click="$emit('navigate', 'all')">
              查看全部 <span aria-hidden="true">›</span>
            </button>
          </div>
          <AppCollection :apps="otherApps" :available="available" @open="$emit('open', $event)" />
        </section>
        <div v-if="!apps.length" class="empty-state" role="status">
          <h2 class="empty-title">
            {{ emptyTitle }}
          </h2>
          <p class="empty-description">
            {{ emptyDescription }}
          </p>
        </div>
      </template>

      <template v-else>
        <AppCollection v-if="visibleApps.length" :apps="visibleApps" :available="available" @open="$emit('open', $event)" />
        <div v-else class="empty-state" role="status">
          <h2 class="empty-title">
            {{ emptyTitle }}
          </h2>
          <p class="empty-description">
            {{ emptyDescription }}
          </p>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
.discovery-content {
  min-height: 0;
  flex: 1;
  overflow: auto;
  container: discovery / inline-size;
  overscroll-behavior: contain;
}
.discovery-inner {
  width: 100%;
  max-width: 1280px;
  margin: 0 auto;
  padding: 32px;
}
.discovery-heading {
  margin-bottom: 20px;
}
.page-title {
  margin: 0;
  font-size: 32px;
  font-weight: 700;
  line-height: 39px;
  letter-spacing: -0.6px;
}
.page-subtitle {
  margin: 8px 0 0;
  color: var(--muted);
  font-size: 15px;
  line-height: 22px;
}
.cook-feature {
  position: relative;
  display: flex;
  min-height: 246px;
  overflow: hidden;
  align-items: center;
  border-radius: 16px;
  background: #b65238;
  color: #fff;
}
.feature-art {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: cover;
  pointer-events: none;
  user-select: none;
}
.feature-copy {
  position: relative;
  z-index: 1;
  padding: 32px;
}
.feature-title {
  margin: 0;
  font-size: 32px;
  font-weight: 700;
  line-height: 1.3;
  letter-spacing: -0.4px;
}
.feature-description {
  margin: 10px 0 18px;
  font-size: 15px;
  line-height: 22px;
}
.feature-button {
  min-width: 112px;
  padding: 7px 20px;
  border: 1px solid rgb(255 255 255 / 70%);
  border-radius: 999px;
  background: #fff;
  color: #292626;
  font-size: 13px;
  font-weight: 600;
  line-height: 20px;
  cursor: pointer;
}
.feature-button:hover:not(:disabled) {
  background: #f1f1f1;
}
.feature-button:disabled {
  opacity: 0.6;
  cursor: default;
}
.collection-section {
  margin-top: 28px;
}
.section-heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 8px;
}
.section-title {
  margin: 0;
  color: var(--text);
  font-size: 20px;
  font-weight: 650;
  line-height: 26px;
  letter-spacing: -0.2px;
}
.see-all {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 4px 0;
  border: 0;
  background: transparent;
  color: var(--accent);
  font-size: 12px;
  line-height: 18px;
  cursor: pointer;
}
.see-all:hover {
  text-decoration: underline;
}
.empty-state {
  padding: 56px 16px;
  text-align: center;
}
.empty-title {
  margin: 0 0 10px;
  font-size: 18px;
  font-weight: 600;
  line-height: 26px;
}
.empty-description {
  margin: 0;
  color: var(--muted);
  font-size: 14px;
  line-height: 22px;
}
@container discovery (max-width: 750px) {
  .discovery-inner {
    padding: 26px;
  }
  .cook-feature {
    min-height: 220px;
  }
  .feature-art {
    width: 135%;
    max-width: none;
    left: auto;
    right: 0;
  }
  .feature-copy {
    padding: 26px;
  }
  .feature-title {
    font-size: 27px;
  }
}
@container discovery (max-width: 640px) {
  .feature-art {
    right: -20%;
  }
  .cook-feature.has-feature-art::after {
    position: absolute;
    inset: 0;
    background: linear-gradient(90deg, rgb(151 66 45 / 75%), rgb(151 66 45 / 5%));
    content: '';
  }
  .feature-title {
    font-size: 25px;
  }
}
</style>
