<script setup lang="ts">
import type { CatalogEntry, GuestCommand, GuestState } from '../../shared/desktop'

const props = defineProps<{ guest?: GuestState, app?: CatalogEntry, refreshing?: boolean }>()
defineEmits<{ command: [command: GuestCommand], browse: [], refresh: [] }>()
const host = computed(() => {
  try {
    return new URL(props.guest?.url || props.app?.websiteUrl || '').hostname
  }
  catch { return '' }
})
</script>

<template>
  <header class="guest-toolbar shell-toolbar">
    <div class="navigation-actions">
      <button class="icon-button" :disabled="!guest?.canGoBack" aria-label="后退" title="后退" @click="$emit('command', 'back')">
        <ShellIcon name="back" />
      </button>
      <button class="icon-button" :disabled="!guest?.canGoForward" aria-label="前进" title="前进" @click="$emit('command', 'forward')">
        <ShellIcon name="forward" />
      </button>
      <button class="icon-button" :disabled="!guest?.open" aria-label="重新加载" title="重新加载" @click="$emit('command', 'reload')">
        <ShellIcon name="refresh" />
      </button>
    </div>
    <div class="guest-location">
      <strong>{{ app?.name || guest?.title || '正在打开应用…' }}</strong><span>{{ guest?.loading ? '正在加载…' : host }}</span>
    </div>
    <button class="toolbar-button" @click="$emit('browse')">
      返回目录
    </button>
    <button class="icon-button" :disabled="refreshing" aria-label="刷新目录" title="刷新目录" @click="$emit('refresh')">
      <ShellIcon name="grid" />
    </button>
    <button class="icon-button" :disabled="!guest?.open" aria-label="关闭应用" title="关闭应用" @click="$emit('command', 'close')">
      <ShellIcon name="close" />
    </button>
  </header>
</template>

<style scoped>
.navigation-actions {
  display: flex;
  align-items: center;
  gap: var(--ylf-space-1);
  padding-right: var(--ylf-space-2);
  border-right: 1px solid var(--border);
}
.guest-location {
  min-width: 0;
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.guest-location strong {
  font-size: var(--ylf-desktop-text-nav);
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.guest-location span {
  color: var(--muted);
  font-size: var(--ylf-desktop-text-meta);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
