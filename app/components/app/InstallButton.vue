<script setup lang="ts">
/**
 * InstallButton - 应用安装按钮
 * 「获取」/「已安装」状态切换
 */
import { IonButton } from '@ionic/vue'

interface Props {
  /** 应用 ID */
  appId: string
}

const props = defineProps<Props>()

const homeScreenStore = useHomeScreenStore()
const { installApp } = useHomeScreen()

const installed = computed(() => homeScreenStore.isInstalled(props.appId))

function handleInstall() {
  if (installed.value)
    return
  installApp(props.appId)
}
</script>

<template>
  <IonButton
    :fill="installed ? 'clear' : 'solid'"
    size="small"
    :color="installed ? 'medium' : 'light'"
    class="install-btn"
    :disabled="installed"
    @click.stop="handleInstall"
  >
    {{ installed ? '已安装' : '获取' }}
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
