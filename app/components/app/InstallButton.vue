<script setup lang="ts">
/**
 * InstallButton - 应用安装/打开按钮
 * 未安装：显示「获取」按钮，点击安装到 Home Screen
 * 已安装：显示「打开」按钮，点击直接打开应用
 */
import type { YlfAppInfo } from '~~/packages/types'
import { IonButton } from '@ionic/vue'

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

const resolvedAppId = computed(() => {
  if (props.app)
    return props.app.slug || props.app.id
  return props.appId || ''
})

const installed = computed(() => homeScreenStore.isInstalled(resolvedAppId.value))

function handleClick() {
  if (installed.value) {
    // 已安装：打开应用
    if (props.app?.url) {
      if (props.app.url.startsWith('http')) {
        openInAppBrowser(props.app.url)
      }
      else {
        router.push(props.app.url)
      }
    }
  }
  else {
    // 未安装：安装到 Home Screen
    installApp(resolvedAppId.value)
  }
}
</script>

<template>
  <IonButton
    fill="solid"
    size="small"
    :color="installed ? 'primary' : 'light'"
    class="install-btn"
    :class="{ 'install-btn--open': installed }"
    @click.stop="handleClick"
  >
    {{ installed ? '打开' : '获取' }}
  </IonButton>
</template>

<style scoped>
.install-btn {
  --border-radius: 100px;
  --padding-start: 18px;
  --padding-end: 18px;
  --box-shadow: none;
  font-weight: 700;
  font-size: 15px;
  min-width: 72px;
  height: 28px;
  letter-spacing: 0.01em;
  text-transform: none;
}

/* 「获取」态：浅灰胶囊底 + 蓝字，对齐 App Store */
.install-btn:not(.install-btn--open) {
  --background: rgba(120, 120, 128, 0.12);
  --background-hover: rgba(120, 120, 128, 0.18);
  --background-activated: rgba(120, 120, 128, 0.24);
  --color: #007aff;
}

/* 暗黑模式「获取」 */
:global(.dark) .install-btn:not(.install-btn--open) {
  --background: rgba(118, 118, 128, 0.24);
  --background-hover: rgba(118, 118, 128, 0.32);
  --background-activated: rgba(118, 118, 128, 0.4);
  --color: #0a84ff;
}

/* 「打开」态：蓝色实心胶囊 + 白字 */
.install-btn--open {
  --background: #007aff;
  --background-hover: #0071e3;
  --background-activated: #0064cc;
  --color: #ffffff;
}

:global(.dark) .install-btn--open {
  --background: #0a84ff;
  --background-hover: #0077ed;
  --background-activated: #006adb;
  --color: #ffffff;
}
</style>
