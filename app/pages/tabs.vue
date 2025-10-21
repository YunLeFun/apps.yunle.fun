<script setup lang="ts">
import {
  IonContent,
  IonIcon,
  IonLabel,
  IonPage,
  IonRouterOutlet,
  IonTabBar,
  IonTabButton,
  IonTabs,
} from '@ionic/vue'
import { apps, compass, home, person } from 'ionicons/icons'

definePageMeta({
  alias: ['/'],
})
</script>

<template>
  <IonPage>
    <IonContent>
      <IonTabs>
        <!-- 路由出口，用于渲染当前激活的标签页内容 -->
        <IonRouterOutlet />

        <!-- 底部标签栏 -->
        <IonTabBar slot="bottom">
          <IonTabButton tab="home" href="/tabs/home">
            <IonIcon :icon="home" />
            <IonLabel>首页</IonLabel>
          </IonTabButton>

          <IonTabButton tab="discovery" href="/tabs/discovery">
            <IonIcon :icon="compass" />
            <IonLabel>发现</IonLabel>
          </IonTabButton>

          <IonTabButton tab="apps" href="/tabs/apps">
            <IonIcon :icon="apps" />
            <IonLabel>应用</IonLabel>
          </IonTabButton>

          <IonTabButton tab="profile" href="/tabs/profile">
            <IonIcon :icon="person" />
            <IonLabel>我的</IonLabel>
          </IonTabButton>
        </IonTabBar>
      </IonTabs>
    </IonContent>
  </IonPage>
</template>
