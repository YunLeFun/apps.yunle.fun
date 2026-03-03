<script setup lang="ts">
import { Capacitor } from '@capacitor/core'
import { actionSheetController } from '@ionic/vue'
import {
  chatbubbleEllipsesOutline,
  mailOutline,
  starOutline,
} from 'ionicons/icons'
import {
  kBlock,
  kBlockTitle,
  kList,
  kListItem,
} from 'konsta/vue'
import { config } from '~/config'
import { YLF_CONTACT } from '~/constants'

const toast = useToast()

/**
 * 去 App Store 评分
 */
function goToAppStore() {
  if (Capacitor.isNativePlatform()) {
    window.open(config.appStore.url, '_system')
  }
  else {
    window.open(config.appStore.url, '_blank')
  }
}

/**
 * 生成邮件模板
 */
function buildMailtoUrl(email: string, type: 'business' | 'support') {
  const subject = type === 'business'
    ? encodeURIComponent('【业务合作】来自云乐坊用户')
    : encodeURIComponent('【问题反馈】来自云乐坊用户')

  const body = type === 'business'
    ? encodeURIComponent(
        `您好，\n\n我对贵平台的业务合作感兴趣，以下是我的信息：\n\n`
        + `公司/个人名称：\n`
        + `联系方式：\n`
        + `合作意向：\n\n`
        + `期待您的回复！\n\n`
        + `---\n`
        + `发送自 云乐坊 (yunle.fun)`,
      )
    : encodeURIComponent(
        `您好，\n\n我在使用云乐坊时遇到了以下问题：\n\n`
        + `问题描述：\n`
        + `操作步骤：\n`
        + `期望结果：\n`
        + `实际结果：\n\n`
        + `设备信息：${navigator.userAgent}\n\n`
        + `---\n`
        + `发送自 云乐坊 (yunle.fun)`,
      )

  return `mailto:${email}?subject=${subject}&body=${body}`
}

/**
 * 点击邮箱 → ActionSheet（复制 / 发送）
 */
async function handleEmailClick(email: string, type: 'business' | 'support') {
  const actionSheet = await actionSheetController.create({
    header: email,
    buttons: [
      {
        text: '复制邮箱',
        handler: async () => {
          try {
            await navigator.clipboard.writeText(email)
            toast.showSuccess('邮箱已复制')
          }
          catch {
            toast.showError('复制失败')
          }
        },
      },
      {
        text: '发送邮件',
        handler: () => {
          window.location.href = buildMailtoUrl(email, type)
        },
      },
      { text: '取消', role: 'cancel' },
    ],
  })
  await actionSheet.present()
}

function openWxKf() {
  window.open(YLF_CONTACT.wxKf.url, '_blank')
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" text="我" />
        </IonButtons>
        <IonTitle>反馈</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <IonHeader collapse="condense">
        <IonToolbar>
          <IonTitle size="large">
            反馈
          </IonTitle>
        </IonToolbar>
      </IonHeader>

      <!-- 反馈 -->
      <k-block-title>联系我们</k-block-title>
      <k-list strong inset>
        <k-list-item
          link
          :title="YLF_CONTACT.support.label"
          :after="YLF_CONTACT.support.email"
          @click="handleEmailClick(YLF_CONTACT.support.email, 'support')"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-orange">
              <IonIcon :icon="chatbubbleEllipsesOutline" />
            </span>
          </template>
        </k-list-item>

        <k-list-item
          link
          :title="YLF_CONTACT.business.label"
          :after="YLF_CONTACT.business.email"
          @click="handleEmailClick(YLF_CONTACT.business.email, 'business')"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-blue">
              <IonIcon :icon="mailOutline" />
            </span>
          </template>
        </k-list-item>

        <k-list-item
          link
          :title="YLF_CONTACT.wxKf.label"
          after="微信"
          @click="openWxKf"
        >
          <template #media>
            <span class="ios-icon-box" style="background-color: #07c160">
              <Icon name="ri:customer-service-2-line" class="text-white" size="18px" />
            </span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 支持我们 -->
      <k-block-title>支持我们</k-block-title>
      <k-list strong inset>
        <k-list-item
          link
          title="去评分"
          after="App Store"
          @click="goToAppStore"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-yellow">
              <IonIcon :icon="starOutline" />
            </span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 社交媒体 -->
      <AppSocialMediaList />

      <!-- 底部说明 -->
      <k-block class="mt-8">
        <p class="text-center text-xs ios-secondary-text">
          我们会尽快回复您的反馈，感谢您的支持！
        </p>
      </k-block>
    </IonContent>
  </IonPage>
</template>
