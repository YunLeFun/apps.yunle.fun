<script setup lang="ts">
import type { BrowseCategory } from '~/utils/appBrowseCategories'
import { IonIcon } from '@ionic/vue'
import { closeCircle, searchOutline } from 'ionicons/icons'

const props = defineProps<{
  categories: BrowseCategory[]
  selected: string
  query: string
  searchPlaceholder: string
  resultCount: number
  loading?: boolean
}>()

const emit = defineEmits<{
  select: [category: string]
  search: [query: string]
}>()

const title = computed(() => props.query.trim()
  ? '搜索结果'
  : props.selected === '全部' ? '全部应用' : props.selected)

const searchInput = useTemplateRef<HTMLInputElement>('search-input')

function search(event: Event) {
  emit('search', (event.target as HTMLInputElement).value)
}

async function clearSearch() {
  emit('search', '')
  await nextTick()
  searchInput.value?.focus()
}
</script>

<template>
  <div class="catalog-browser">
    <aside class="catalog-navigation">
      <WorkshopCatalogCategories
        :categories="categories"
        :selected="selected"
        @select="emit('select', $event)"
      />
    </aside>

    <main class="catalog-main">
      <header class="catalog-heading">
        <div class="catalog-title-group">
          <h1 class="catalog-title">
            {{ title }}
          </h1>
          <p class="catalog-result-count" role="status" aria-live="polite">
            {{ loading ? '正在加载应用…' : `${resultCount} 款应用` }}
          </p>
        </div>

        <div class="catalog-search">
          <IonIcon class="search-icon" :icon="searchOutline" aria-hidden="true" />
          <input
            ref="search-input"
            :value="query"
            type="search"
            inputmode="search"
            aria-label="搜索应用"
            :placeholder="searchPlaceholder"
            class="catalog-search-input"
            @input="search"
          >
          <button
            v-if="query"
            type="button"
            class="search-clear"
            aria-label="清除搜索"
            @click="clearSearch"
          >
            <IonIcon :icon="closeCircle" aria-hidden="true" />
          </button>
        </div>
      </header>

      <div class="catalog-mobile-navigation">
        <WorkshopCatalogCategories
          :categories="categories"
          :selected="selected"
          @select="emit('select', $event)"
        />
      </div>

      <slot />
    </main>
  </div>
</template>

<style scoped>
.catalog-browser {
  max-width: 1160px;
  margin: 0 auto;
  padding: 20px 20px 36px;
  color: var(--ylf-catalog-text);
  font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'PingFang SC', sans-serif;
}

.catalog-navigation {
  display: none;
  min-width: 0;
}

.catalog-main {
  min-width: 0;
}

.catalog-heading {
  display: flex;
  flex-direction: column;
  gap: 20px;
  margin-bottom: 16px;
}

.catalog-title {
  margin: 0;
  font-size: 30px;
  font-weight: 700;
  line-height: 1.2;
  letter-spacing: -0.025em;
}

.catalog-result-count {
  margin: 7px 0 0;
  color: var(--ylf-catalog-text-secondary);
  font-size: 13px;
  line-height: 1.4;
}

.catalog-search {
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 0 12px;
  border: 1px solid transparent;
  border-radius: 10px;
  background: var(--ylf-catalog-control);
  color: var(--ylf-catalog-control-secondary);
}

.catalog-search:focus-within {
  border-color: var(--ylf-catalog-accent);
  outline: 2px solid var(--ylf-catalog-accent-soft);
}

.search-icon {
  flex: 0 0 auto;
  font-size: 18px;
}

.catalog-search-input {
  width: 100%;
  min-width: 0;
  height: 40px;
  padding: 0;
  border: 0;
  outline: 0;
  background: transparent;
  color: var(--ylf-catalog-text);
  font: inherit;
  font-size: 16px;
}

.catalog-search-input::placeholder {
  color: var(--ylf-catalog-control-secondary);
  opacity: 1;
}

.catalog-search-input::-webkit-search-cancel-button {
  display: none;
}

.search-clear {
  width: 28px;
  height: 36px;
  display: grid;
  flex: 0 0 auto;
  place-items: center;
  padding: 0;
  border: 0;
  border-radius: 5px;
  background: transparent;
  color: var(--ylf-catalog-control-secondary);
  font-size: 19px;
  cursor: pointer;
}

.search-clear:focus-visible {
  outline: 2px solid var(--ylf-catalog-accent);
}

.catalog-mobile-navigation {
  margin-bottom: 6px;
}

@media (min-width: 900px) {
  .catalog-browser {
    display: grid;
    grid-template-columns: 184px minmax(0, 1fr);
    align-items: start;
    gap: 36px;
    padding: 32px 28px 48px;
  }

  .catalog-navigation {
    display: block;
  }

  .catalog-heading {
    flex-direction: row;
    align-items: center;
    justify-content: space-between;
    gap: 24px;
    margin-bottom: 24px;
  }

  .catalog-title {
    font-size: 32px;
  }

  .catalog-search {
    width: 280px;
    flex: 0 1 280px;
  }

  .catalog-mobile-navigation {
    display: none;
  }
}

@media (max-width: 359px) {
  .catalog-browser {
    padding-inline: 16px;
  }
}
</style>
