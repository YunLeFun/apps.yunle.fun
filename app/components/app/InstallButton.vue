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
    :fill="installed ? 'solid' : 'solid'"
    size="small"
    :color="installed ? 'primary' : 'light'"
    class="install-btn"
    @click.stop="handleClick"
  >
    {{ installed ? '打开' : '获取' }}
  </IonButton>
</template>

<style scoped>
.install-btn {
  --border-radius: 14px;
  --padding-start: 16px;
  --padding-end: 16px;
  font-weight: 600;
  font-size: 15px;
  min-width: 72px;
  height: 32px;
}
</style>
