<script setup lang="ts">
import {
  IonButton,
  IonContent,
  IonHeader,
  IonPage,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'

const showScanner = ref(false)
const scanResult = ref('')
const { showInfo } = useToast()

function openScanner() {
  showScanner.value = true
}

function handleScanResult(content: string) {
  scanResult.value = content
  showScanner.value = false
  showInfo(`扫码成功：${content}`)
}

function handleScanCancel() {
  showScanner.value = false
  showInfo('已取消扫码')
}
</script>

<template>
  <IonPage>
    <IonHeader>
      <IonToolbar>
        <IonTitle>扫码测试</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent class="ion-padding">
      <div class="test-container">
        <h2>扫码功能测试</h2>

        <IonButton expand="block" @click="openScanner">
          打开扫码
        </IonButton>

        <div v-if="scanResult" class="result-box">
          <h3>扫码结果：</h3>
          <p>{{ scanResult }}</p>
        </div>

        <div class="info-box">
          <h3>使用说明：</h3>
          <ul>
            <li>点击「打开扫码」按钮</li>
            <li>对准二维码或条形码</li>
            <li>等待自动识别</li>
            <li>查看扫码结果</li>
          </ul>
        </div>
      </div>

      <!-- 扫码组件 -->
      <ScannerBarcode
        :is-visible="showScanner"
        :show-flashlight="true"
        @cancel="handleScanCancel"
        @result="handleScanResult"
      />
    </IonContent>
  </IonPage>
</template>

<style scoped>
.test-container {
  max-width: 600px;
  margin: 0 auto;
  padding: 20px;
}

h2 {
  margin-bottom: 24px;
  text-align: center;
}

.result-box {
  margin-top: 24px;
  padding: 16px;
  background: var(--ion-color-light);
  border-radius: 8px;
}

.result-box h3 {
  margin-bottom: 8px;
  font-size: 16px;
  font-weight: 600;
}

.result-box p {
  margin: 0;
  word-break: break-all;
}

.info-box {
  margin-top: 32px;
  padding: 16px;
  background: var(--ion-color-light);
  border-radius: 8px;
}

.info-box h3 {
  margin-bottom: 12px;
  font-size: 16px;
  font-weight: 600;
}

.info-box ul {
  margin: 0;
  padding-left: 20px;
}

.info-box li {
  margin-bottom: 8px;
}
</style>
