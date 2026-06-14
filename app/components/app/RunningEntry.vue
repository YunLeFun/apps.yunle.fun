<script setup lang="ts">
/**
 * AppRunningEntry - 云居首页左上角「正在运行」入口
 *
 * 仅当有后台保活会话时出现（图标 + 数量角标）；点击展开 Popover 面板
 * （AppRunningPanel：恢复 / 单个关闭 / 一键清理）。放在 IonToolbar 的 slot="start"。
 */
import { IonButton, IonIcon, IonPopover } from '@ionic/vue'
import { copyOutline } from 'ionicons/icons'

const { sessions } = useBackgroundSessions()

const open = ref(false)
const triggerEvent = ref<Event | undefined>()

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
    :is-open="open"
    :event="triggerEvent"
    :show-backdrop="false"
    style="--width: 264px;"
    @did-dismiss="open = false"
  >
    <AppRunningPanel @close="open = false" />
  </IonPopover>
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
