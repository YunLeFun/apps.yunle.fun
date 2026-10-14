<script setup lang="ts">
import {
  IonIcon,
  IonLabel,
  IonPage,
  IonRouterOutlet,
  IonTabBar,
  IonTabButton,
  IonTabs,
} from '@ionic/vue'
import { apps, compass, home, person } from 'ionicons/icons'

const agentScreenOpen = useState('agent:screen-open', () => false)
</script>

<template>
  <IonPage>
    <IonTabs>
      <!-- 路由出口，用于渲染当前激活的标签页内容 -->
      <IonRouterOutlet />

      <!-- 底部标签栏 -->
      <IonTabBar v-show="!agentScreenOpen" slot="bottom">
        <!-- 命名彩蛋：前三个核心 Tab 各取“云 / 乐 / 坊”，合起来是“云乐坊”，详见 docs/product/tabs-architecture.md -->
        <IonTabButton tab="home" href="/tabs/home">
          <IonIcon :icon="home" />
          <IonLabel>云居</IonLabel>
        </IonTabButton>

        <IonTabButton tab="discovery" href="/tabs/discovery">
          <IonIcon :icon="compass" />
          <IonLabel>寻乐</IonLabel>
        </IonTabButton>

        <IonTabButton tab="apps" href="/tabs/apps">
          <IonIcon :icon="apps" />
          <IonLabel>工坊</IonLabel>
        </IonTabButton>

        <IonTabButton tab="me" href="/tabs/me">
          <IonIcon :icon="person" />
          <IonLabel>我</IonLabel>
        </IonTabButton>
      </IonTabBar>
    </IonTabs>
  </IonPage>
</template>
