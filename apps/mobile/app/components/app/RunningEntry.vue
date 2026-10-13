<script setup lang="ts">
/**
 * AppRunningEntry - 云居首页左上角「正在运行」入口
 *
 * 仅当有后台保活会话时出现（图标 + 数量角标）；紧凑屏使用 Bottom Sheet，
 * 宽屏使用 Popover。两种容器复用 AppRunningPanel。
 */
import { IonButton, IonIcon, IonModal, IonPopover } from '@ionic/vue'
import { useMediaQuery } from '@vueuse/core'
import { copyOutline } from 'ionicons/icons'
// 显式同步导入（不走自动导入）：避免 Nuxt 测试环境下该组件异步 import
// 在环境拆除后才 resolve（EnvironmentTeardownError，CI 时序相关）
import RunningPanel from './RunningPanel.vue'

const { sessions } = useBackgroundSessions()

const open = shallowRef(false)
const triggerEvent = shallowRef<Event | undefined>()
const isCompact = useMediaQuery('(max-width: 599px)')

const sheetInitialBreakpoint = computed(() => {
  if (sessions.value.length <= 3)
    return 0.36
  if (sessions.value.length <= 6)
    return 0.56
  return 0.72
})

const sheetBreakpoints = computed(() => [0, sheetInitialBreakpoint.value, 0.9])

watch(isCompact, () => {
  open.value = false
})

function openPanel(e: Event) {
  triggerEvent.value = e
  open.value = true
}
</script>

<template>
  <IonButton
    v-if="sessions.length"
    class="running-entry-btn"
    :aria-label="`正在运行的应用，${sessions.length} 个`"
    @click="openPanel"
  >
    <IonIcon slot="icon-only" :icon="copyOutline" />
    <span class="running-entry-badge">{{ sessions.length }}</span>
  </IonButton>

  <IonPopover
    v-if="!isCompact"
    :is-open="open"
    :event="triggerEvent"
    :show-backdrop="false"
    css-class="ylf-elevated-popover running-sessions-popover"
    @did-dismiss="open = false"
  >
    <RunningPanel v-if="open" presentation="popover" @close="open = false" />
  </IonPopover>

  <IonModal
    v-else
    class="running-sessions-sheet"
    :is-open="open"
    :breakpoints="sheetBreakpoints"
    :initial-breakpoint="sheetInitialBreakpoint"
    handle-behavior="cycle"
    @did-dismiss="open = false"
  >
    <RunningPanel v-if="open" presentation="sheet" @close="open = false" />
  </IonModal>
</template>

<style scoped>
.running-entry-btn {
  position: relative;
  overflow: visible;
}

.running-entry-badge {
  position: absolute;
  top: 2px;
  right: -2px;
  min-width: 15px;
  height: 15px;
  padding: 0 3px;
  font-size: 10px;
  font-weight: 700;
  line-height: 15px;
  text-align: center;
  color: #fff;
  background: var(--ion-color-danger, #eb445a);
  border-radius: 999px;
  pointer-events: none;
}
</style>
