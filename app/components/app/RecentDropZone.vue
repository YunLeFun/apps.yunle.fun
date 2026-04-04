<script setup lang="ts">
/**
 * AppRecentDropZone - 最近使用拖拽操作栏
 *
 * 长按拖拽时从底部滑入，提供「添加到我的」和「删除」两个拖放目标区域。
 */
import type { DropZoneType } from '~/composables/useRecentDrag'
import { IonIcon } from '@ionic/vue'
import { addCircleOutline, trashOutline } from 'ionicons/icons'

defineProps<{
  /** 是否可见（拖拽中） */
  visible: boolean
  /** 当前高亮的区域 */
  activeZone: DropZoneType
}>()
</script>

<template>
  <Teleport to="body">
    <Transition name="drop-zone-slide">
      <div v-if="visible" class="recent-drop-zone">
        <div
          class="drop-action add-action"
          :class="{ active: activeZone === 'add' }"
        >
          <IonIcon :icon="addCircleOutline" class="drop-icon" />
          <span class="drop-label">拖到此处添加到我的</span>
        </div>
        <div class="drop-divider" />
        <div
          class="drop-action delete-action"
          :class="{ active: activeZone === 'delete' }"
        >
          <IonIcon :icon="trashOutline" class="drop-icon" />
          <span class="drop-label">拖到此处删除</span>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.recent-drop-zone {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  height: 100px;
  z-index: 100002;
  display: flex;
  align-items: center;
  justify-content: center;
  padding-bottom: env(safe-area-inset-bottom, 0);

  /* 毛玻璃背景 */
  background: rgba(255, 255, 255, 0.85);
  backdrop-filter: blur(20px) saturate(180%);
  -webkit-backdrop-filter: blur(20px) saturate(180%);
  border-top: 0.5px solid rgba(0, 0, 0, 0.1);
}

.dark .recent-drop-zone {
  background: rgba(28, 28, 30, 0.85);
  border-top-color: rgba(255, 255, 255, 0.1);
}

.drop-action {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 6px;
  height: 100%;
  transition: all 0.2s cubic-bezier(0.34, 1.56, 0.64, 1);
  pointer-events: none;
  border-radius: 0;
}

.drop-action.active {
  transform: scale(1.05);
}

.drop-action.add-action.active {
  background: rgba(0, 122, 255, 0.15);
}

.dark .drop-action.add-action.active {
  background: rgba(10, 132, 255, 0.2);
}

.drop-action.delete-action.active {
  background: rgba(255, 59, 48, 0.15);
}

.dark .drop-action.delete-action.active {
  background: rgba(255, 69, 58, 0.2);
}

.drop-divider {
  width: 0.5px;
  height: 48px;
  background: rgba(0, 0, 0, 0.12);
  flex-shrink: 0;
}

.dark .drop-divider {
  background: rgba(255, 255, 255, 0.12);
}

.drop-icon {
  font-size: 28px;
  color: #007aff;
  transition: color 0.2s ease, transform 0.2s ease;
}

.delete-action .drop-icon {
  color: #ff3b30;
}

.dark .drop-icon {
  color: #0a84ff;
}

.dark .delete-action .drop-icon {
  color: #ff453a;
}

.drop-action.active .drop-icon {
  transform: scale(1.15);
}

.drop-label {
  font-size: 12px;
  font-weight: 600;
  color: #007aff;
  transition: color 0.2s ease;
}

.delete-action .drop-label {
  color: #ff3b30;
}

.dark .drop-label {
  color: #0a84ff;
}

.dark .delete-action .drop-label {
  color: #ff453a;
}

/* Slide-up transition（线性进入，无 bounce） */
.drop-zone-slide-enter-active {
  transition: transform 0.25s ease-out, opacity 0.2s ease-out;
}

.drop-zone-slide-leave-active {
  transition: transform 0.2s ease-in, opacity 0.15s ease-in;
}

.drop-zone-slide-enter-from {
  transform: translateY(100%);
  opacity: 0;
}

.drop-zone-slide-leave-to {
  transform: translateY(100%);
  opacity: 0;
}
</style>
