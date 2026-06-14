<script setup lang="ts">
/**
 * AppRunningPanel - 「正在运行」展开面板（云居首页左上角按钮触发的 Popover 内容）
 *
 * - 轻点某行：恢复该后台会话（秒回页面状态），并关闭面板
 * - 行尾 ✕：单个关闭
 * - 顶部「一键清理」：结束并释放全部
 */
import type { BackgroundSession } from '~/composables/useBrowser'
import { actionSheetController } from '@ionic/vue'
import { closeOutline, trashOutline } from 'ionicons/icons'

const emit = defineEmits<{ close: [] }>()

const { sessions, resume, end, clearAll } = useBackgroundSessions()

function onResume(s: BackgroundSession) {
  emit('close')
  resume(s)
}

/** 一键清理为破坏性操作，先确认（对齐 iOS「关闭全部标签页」的 action sheet 模式） */
async function onClearAll() {
  const count = sessions.value.length
  const sheet = await actionSheetController.create({
    buttons: [
      { text: `结束全部 ${count} 个应用`, role: 'destructive', handler: () => {
        emit('close')
        void clearAll()
      } },
      { text: '取消', role: 'cancel' },
    ],
  })
  await sheet.present()
}
</script>

<template>
  <div class="running-panel">
    <div class="running-panel-head">
      <span class="running-panel-title">正在运行 · {{ sessions.length }}</span>
      <button
        v-if="sessions.length"
        type="button"
        class="running-clear"
        @click="onClearAll"
      >
        <IonIcon :icon="trashOutline" />
        一键清理
      </button>
    </div>

    <div v-if="sessions.length" class="running-list">
      <div v-for="s in sessions" :key="s.key" class="running-row">
        <button type="button" class="running-row-main" @click="onResume(s)">
          <AppIconBox
            class="running-row-iconbox"
            :icon="s.logo"
            :emoji="s.emoji || '🌐'"
            :color="s.themeColor"
            size="grid"
          />
          <span class="running-row-name">{{ s.name }}</span>
        </button>
        <button
          type="button"
          class="running-row-close"
          aria-label="关闭"
          @click="end(s)"
        >
          <IonIcon :icon="closeOutline" />
        </button>
      </div>
    </div>

    <div v-else class="running-empty">
      没有正在运行的应用
    </div>
  </div>
</template>

<style scoped>
.running-panel {
  width: 100%;
  box-sizing: border-box;
  padding: 6px 6px 8px;
  overflow: hidden;
}

.running-panel-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 6px 8px 8px;
}

.running-panel-title {
  font-size: 13px;
  font-weight: 600;
  color: var(--ion-color-medium, #8e8e93);
}

.running-clear {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  font-size: 12px;
  color: var(--ion-color-danger, #eb445a);
  background: none;
  border: none;
  padding: 2px 4px;
  cursor: pointer;
}

.running-list {
  display: flex;
  flex-direction: column;
  max-height: 50vh;
  overflow-y: auto;
}

.running-row {
  display: flex;
  align-items: center;
  border-radius: 12px;
}

.running-row:active {
  background: var(--ylf-fill-secondary, rgba(120, 120, 128, 0.12));
}

.running-row-main {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 12px;
  min-width: 0;
  background: none;
  border: none;
  padding: 6px 4px 6px 8px;
  cursor: pointer;
}

/* 面板内图标用更小尺寸（列表行） */
.running-row-iconbox {
  --app-icon-size: 40px;
  --app-icon-radius: 10px;
  --app-emoji-size: 20px;
  flex-shrink: 0;
}

.running-row-name {
  flex: 1;
  min-width: 0;
  font-size: 15px;
  color: var(--ion-text-color);
  text-align: left;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.running-row-close {
  flex-shrink: 0;
  width: 32px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-right: 4px;
  font-size: 18px;
  color: var(--ion-color-medium, #8e8e93);
  background: none;
  border: none;
  cursor: pointer;
}

.running-empty {
  padding: 8px;
  text-align: center;
  font-size: 13px;
  color: var(--ion-color-medium, #8e8e93);
}
</style>
