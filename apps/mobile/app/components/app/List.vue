<script setup lang="ts">
import type { YlfAppInfo } from '@yunlefun/types'
import { IonInfiniteScroll, IonInfiniteScrollContent, IonSpinner } from '@ionic/vue'

const router = useRouter()
const { apps, loading, hasMore, initialized, loadMore, selectedCategory, searchQuery } = useWorkshop()

function openAppDetail(app: YlfAppInfo) {
  router.push(`/app/${app.slug || app.id}`)
}

async function handleInfiniteScroll(event: CustomEvent) {
  loadMore()
  await nextTick()
  ;(event.target as HTMLIonInfiniteScrollElement).complete()
}
</script>

<template>
  <div class="catalog-list">
    <div v-if="loading && !initialized" class="catalog-loading">
      <IonSpinner name="crescent" />
    </div>
    <template v-else>
      <div v-if="apps.length" class="catalog-app-grid">
        <WorkshopCatalogRow
          v-for="app in apps"
          :key="app.id"
          :app="app"
          @open="openAppDetail(app)"
        />
      </div>
      <div v-else class="catalog-empty">
        <strong>{{ searchQuery || selectedCategory !== '全部' ? '没有匹配的应用' : '这里还没有应用' }}</strong>
        <p>{{ searchQuery || selectedCategory !== '全部' ? '试试其他分类，或换个关键词。' : '新应用发布后会显示在这里。' }}</p>
      </div>
      <IonInfiniteScroll v-if="hasMore && apps.length" @ion-infinite="handleInfiniteScroll">
        <IonInfiniteScrollContent loading-spinner="crescent" />
      </IonInfiniteScroll>
    </template>
  </div>
</template>

<style scoped>
.catalog-app-grid {
  display: grid;
  grid-template-columns: minmax(0, 1fr);
}

.catalog-loading,
.catalog-empty {
  min-height: 240px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  color: var(--ylf-catalog-text-secondary);
  text-align: center;
}

.catalog-empty strong {
  color: var(--ylf-catalog-text);
  font-size: 16px;
  font-weight: 600;
}

.catalog-empty p {
  margin: 8px 0 0;
  font-size: 13px;
  line-height: 1.5;
}

@media (min-width: 1100px) {
  .catalog-app-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
    column-gap: 32px;
  }
}
</style>
