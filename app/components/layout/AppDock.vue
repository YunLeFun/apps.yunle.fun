<script setup lang="ts">
/**
 * AppDock - iPhone 风格底部 Dock 导航栏组件
 *
 * @description
 * 提供类似 iOS 的底部固定导航栏，支持自定义图标、渐变色和路由跳转
 *
 * @example
 * ```vue
 * <AppDock :items="dockItems" />
 * ```
 */

export interface DockItem {
  /** 路由路径 */
  path: string
  /** 显示的 emoji 图标 */
  emoji: string
  /** 背景渐变色 CSS */
  gradient: string
  /** 可选的标签文本 */
  label?: string
}

interface Props {
  /** Dock 项目列表 */
  items: DockItem[]
  /** 是否显示 Dock */
  visible?: boolean
  /** 底部距离（px） */
  bottom?: number
}

withDefaults(defineProps<Props>(), {
  visible: true,
  bottom: 24,
})

const router = useRouter()

/**
 * 处理 Dock 项目点击
 */
function handleItemClick(item: DockItem) {
  router.push(item.path)
}
</script>

<template>
  <Transition name="dock-fade">
    <div
      v-if="visible"
      class="app-dock"
      :style="{ bottom: `${bottom}px` }"
    >
      <div class="dock-container">
        <div
          v-for="(item, index) in items"
          :key="index"
          class="dock-item"
          :title="item.label"
          @click="handleItemClick(item)"
        >
          <div
            class="dock-icon"
            :style="{ background: item.gradient }"
          >
            <span class="dock-emoji">{{ item.emoji }}</span>
          </div>
        </div>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
/* ==================== iPhone Dock ==================== */
.app-dock {
  position: fixed;
  left: 0;
  right: 0;
  display: flex;
  justify-content: center;
  align-items: center;
  padding: 0 16px 8px 16px;
  z-index: 50;
  pointer-events: none;
}

.dock-container {
  display: flex;
  gap: 20px;
  background: rgba(255, 255, 255, 0.7);
  backdrop-filter: blur(30px) saturate(180%);
  -webkit-backdrop-filter: blur(30px) saturate(180%);
  border-radius: 20px;
  padding: 8px 16px;
  box-shadow:
    0 8px 32px rgba(0, 0, 0, 0.12),
    0 0 0 0.5px rgba(0, 0, 0, 0.05);
  pointer-events: auto;
}

.dark .dock-container {
  background: rgba(28, 28, 30, 0.7);
  box-shadow:
    0 8px 32px rgba(0, 0, 0, 0.4),
    0 0 0 0.5px rgba(255, 255, 255, 0.1);
}

.dock-item {
  cursor: pointer;
  transition: transform 0.2s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.dock-item:active {
  transform: scale(0.85);
}

.dock-icon {
  width: 64px;
  height: 64px;
  border-radius: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 3px 10px rgba(0, 0, 0, 0.12);
  position: relative;
  overflow: hidden;
}

.dock-icon::after {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: 16px;
  box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.08);
  pointer-events: none;
}

.dark .dock-icon {
  box-shadow: 0 3px 10px rgba(0, 0, 0, 0.35);
}

.dock-emoji {
  font-size: 32px;
  line-height: 1;
  filter: drop-shadow(0 1px 2px rgba(0, 0, 0, 0.2));
}

/* ==================== 动画 ==================== */
.dock-fade-enter-active,
.dock-fade-leave-active {
  transition: all 0.3s ease;
}

.dock-fade-enter-from,
.dock-fade-leave-to {
  opacity: 0;
  transform: translateY(20px);
}

/* ==================== Dock 悬停效果（桌面端）==================== */
@media (hover: hover) {
  .dock-item:hover {
    transform: translateY(-4px) scale(1.05);
  }

  .dock-item:active {
    transform: translateY(-2px) scale(0.95);
  }
}

/* ==================== 响应式设计 ==================== */
@media (max-width: 480px) {
  .dock-container {
    gap: 16px;
    padding: 8px 12px;
    border-radius: 18px;
  }

  .dock-icon {
    width: 60px;
    height: 60px;
    border-radius: 14px;
  }

  .dock-emoji {
    font-size: 28px;
  }
}

@media (min-width: 768px) {
  .dock-container {
    gap: 24px;
    padding: 10px 16px;
    border-radius: 22px;
  }

  .dock-icon {
    width: 72px;
    height: 72px;
    border-radius: 18px;
  }

  .dock-emoji {
    font-size: 36px;
  }
}

@media (min-width: 1024px) {
  .dock-container {
    gap: 28px;
    padding: 12px 20px;
    border-radius: 24px;
  }

  .dock-icon {
    width: 80px;
    height: 80px;
    border-radius: 20px;
  }

  .dock-emoji {
    font-size: 40px;
  }
}

/* ==================== 无障碍优化 ==================== */
@media (prefers-reduced-motion: reduce) {
  .dock-item,
  .dock-fade-enter-active,
  .dock-fade-leave-active {
    transition: none;
    animation: none;
  }
}
</style>
