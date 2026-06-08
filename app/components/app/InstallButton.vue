<script setup lang="ts">
/**
 * InstallButton - 应用安装/打开按钮
 *
 * 参考 iOS App Store 交互规范：
 * - 未安装：显示「获取」胶囊按钮
 * - 点击获取：按钮收缩为圆环 loading 动画（模拟下载安装）
 * - 安装完成：圆环结束，按钮展开为「打开」
 * - 已安装：显示「打开」按钮，点击直接打开应用
 */
import type { YlfAppInfo } from '@yunlefun/types'

interface Props {
  /** 完整应用对象（推荐），用于已安装时打开应用 */
  app?: YlfAppInfo
  /** 应用 ID（向后兼容，优先使用 app.slug || app.id） */
  appId?: string
}

const props = defineProps<Props>()

const router = useRouter()
const homeScreenStore = useHomeScreenStore()
const { installApp } = useHomeScreen()

/** 安装中（圆环 loading 态） */
const installing = ref(false)

const resolvedAppId = computed(() => {
  if (props.app)
    return props.app.slug || props.app.id
  return props.appId || ''
})

const installed = computed(() => homeScreenStore.isInstalled(resolvedAppId.value))

function handleClick() {
  if (installing.value)
    return

  if (installed.value) {
    if (props.app?.websiteUrl) {
      if (props.app.websiteUrl.startsWith('http')) {
        openInAppBrowser(props.app.websiteUrl)
      }
      else {
        router.push(props.app.websiteUrl)
      }
    }
  }
  else {
    handleInstall()
  }
}

/** 模拟 App Store 安装流程：收缩 → 圆环 → 展开，同时预加载资源 */
function handleInstall() {
  installing.value = true

  // 安装动画期间并行预加载资源，打开时零延迟
  prefetchAppResources()

  setTimeout(() => {
    installApp(resolvedAppId.value)
    installing.value = false
  }, 600)
}

/**
 * 预加载应用资源，利用安装动画的等待时间
 * - 外部链接：DNS prefetch + preconnect（加速首次打开）
 * - 内部路由：preloadRouteComponents（预加载组件 chunk）
 * - 应用详情页：始终预加载 /app/[slug] 路由
 */
function prefetchAppResources() {
  const url = props.app?.websiteUrl
  const appId = resolvedAppId.value

  if (url?.startsWith('http')) {
    // 对外部链接做 DNS 预解析 + 预连接
    try {
      const origin = new URL(url).origin
      appendLinkHint('dns-prefetch', origin)
      appendLinkHint('preconnect', origin)
    }
    catch {}
  }
  else if (url) {
    // 内部路由：预加载路由组件
    preloadRouteComponents(url)
  }

  // 始终预加载应用详情页（用户安装后大概率会查看）
  if (appId) {
    preloadRouteComponents(`/app/${appId}`)
  }
}

/** 向 <head> 插入 link hint（dns-prefetch / preconnect），避免重复 */
function appendLinkHint(rel: 'dns-prefetch' | 'preconnect', href: string) {
  if (document.querySelector(`link[rel="${rel}"][href="${href}"]`))
    return
  const link = document.createElement('link')
  link.rel = rel
  link.href = href
  document.head.appendChild(link)
}
</script>

<template>
  <button
    class="install-btn"
    :class="{
      'install-btn--open': installed,
      'install-btn--installing': installing,
    }"
    :disabled="installing"
    @click.stop="handleClick"
  >
    <!-- 圆环 loading -->
    <svg
      v-if="installing"
      class="install-btn__spinner"
      viewBox="0 0 24 24"
    >
      <circle
        cx="12"
        cy="12"
        r="10"
        fill="none"
        stroke="currentColor"
        stroke-width="2.5"
        stroke-linecap="round"
        stroke-dasharray="48 64"
      />
    </svg>
    <!-- 按钮文字 -->
    <span v-else class="install-btn__label">
      {{ installed ? '打开' : '获取' }}
    </span>
  </button>
</template>

<style scoped>
.install-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border: none;
  border-radius: 100px;
  font-weight: 700;
  font-size: 15px;
  min-width: 72px;
  height: 28px;
  padding: 0 18px;
  letter-spacing: 0.01em;
  text-transform: none;
  cursor: pointer;
  user-select: none;
  -webkit-tap-highlight-color: transparent;
  transition:
    min-width 0.3s ease,
    padding 0.3s ease,
    background-color 0.25s ease;
}

.install-btn:active {
  opacity: 0.7;
}

/* 「获取」态：浅灰胶囊底 + 蓝字，对齐 App Store */
.install-btn:not(.install-btn--open):not(.install-btn--installing) {
  background: var(--ylf-fill-tertiary);
  color: var(--ion-color-primary);
}

/* 「安装中」态：收缩为圆形，仅显示圆环 */
.install-btn--installing {
  min-width: 28px;
  width: 28px;
  padding: 0;
  background: transparent;
  color: var(--ion-color-primary);
  cursor: default;
  pointer-events: none;
}

/* 「打开」态：蓝色实心胶囊 + 白字 */
.install-btn--open {
  background: var(--ion-color-primary);
  color: #fff;
}

.install-btn--open:active {
  background: var(--ion-color-primary-shade);
}

/* 旋转圆环 spinner */
.install-btn__spinner {
  width: 20px;
  height: 20px;
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

/* 文字淡入 */
.install-btn__label {
  animation: fadeIn 0.2s ease;
}

@keyframes fadeIn {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}
</style>
