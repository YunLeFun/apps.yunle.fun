<script setup lang="ts">
import type { GuestCommand, GuestState } from '../../shared/desktop'

defineProps<{ guest?: GuestState }>()
defineEmits<{ command: [command: GuestCommand] }>()
</script>

<template>
  <header class="guest-toolbar">
    <div class="navigation-actions">
      <button class="button compact" :disabled="!guest?.canGoBack" aria-label="后退" @click="$emit('command', 'back')">
        ←
      </button>
      <button class="button compact" :disabled="!guest?.canGoForward" aria-label="前进" @click="$emit('command', 'forward')">
        →
      </button>
      <button class="button compact" :disabled="!guest?.open" aria-label="重新加载" @click="$emit('command', 'reload')">
        ↻
      </button>
    </div>
    <div class="guest-location">
      <strong>{{ guest?.title || (guest?.open ? '正在打开应用…' : '你的云应用') }}</strong>
      <span>{{ guest?.loading ? '正在加载…' : guest?.url || '从左侧目录选择应用' }}</span>
    </div>
    <button class="button" :disabled="!guest?.open" @click="$emit('command', 'close')">
      关闭应用
    </button>
  </header>
</template>

<style scoped>
.guest-toolbar {
  display: flex;
  align-items: center;
  gap: 14px;
  padding-bottom: 18px;
}
.navigation-actions {
  display: flex;
  align-items: center;
  gap: 6px;
}
.guest-location {
  min-width: 0;
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 5px;
}
.guest-location strong {
  font-size: 13px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.guest-location span {
  font-size: 11px;
  color: var(--muted);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
