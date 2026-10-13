<script setup lang="ts">
/**
 * 扫码页面
 *
 * 独立全屏页面，统一扫码入口。
 * - 内嵌 ScannerBarcode 组件（始终 visible）
 * - 扫码成功 → resolveScan(result)
 * - 取消 → cancelScan()
 * - 相册 → 复用 useScanner 的 scanFromAlbum()
 */

import { IonButton, IonButtons, IonContent, IonHeader, IonIcon, IonPage, IonTitle, IonToolbar } from '@ionic/vue'
import { chevronBackOutline } from 'ionicons/icons'

const { resolveScan, cancelScan } = useScanBridge()
const { scanFromAlbum } = useScanner()

function handleResult(content: string) {
  resolveScan(content)
}

function handleCancel() {
  cancelScan()
}

async function handlePickAlbum() {
  const result = await scanFromAlbum()
  if (result) {
    resolveScan(result)
  }
}
</script>

<template>
  <IonPage>
    <IonHeader class="scan-header">
      <IonToolbar>
        <IonButtons slot="start">
          <!-- 不用 IonBackButton：其内置返回导航会与 cancelScan() 的 router.back() 叠加造成双重返回 -->
          <IonButton @click="handleCancel">
            <IonIcon slot="start" :icon="chevronBackOutline" />
            返回
          </IonButton>
        </IonButtons>
        <IonTitle>
          扫一扫
        </IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true" class="scan-page-content">
      <!-- 头部已有「返回」，不再显示底部取消按钮，避免同一动作双入口 -->
      <ScannerBarcode
        :is-visible="true"
        :show-flashlight="true"
        :show-close="false"
        @cancel="handleCancel"
        @result="handleResult"
        @pick-album="handlePickAlbum"
      />
    </IonContent>
  </IonPage>
</template>

<style scoped>
.scan-header {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  z-index: 10001;
}

.scan-header ion-toolbar {
  --background: transparent;
  --border-width: 0;
  --color: #fff;
}

.scan-header ion-back-button {
  --color: #fff;
}

.scan-header ion-title {
  --color: #fff;
}

.scan-page-content {
  --background: #000;
}
</style>
