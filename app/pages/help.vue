<script setup lang="ts">
import {
  bookOutline,
  chevronBackOutline,
  chevronForwardOutline,
  compassOutline,
} from 'ionicons/icons'
import {
  kBlock,
  kBlockTitle,
  kButton,
  kList,
  kListItem,
} from 'konsta/vue'

const router = useRouter()

/**
 * 新手引导步骤
 */
const guideSteps = [
  { emoji: '🔍', title: '发现应用', desc: '在首页浏览推荐应用，或使用搜索快速找到想要的工具', action: '去首页看看', route: '/tabs/home' },
  { emoji: '🚀', title: '使用应用', desc: '点击应用卡片即可直接使用，无需额外下载安装', action: '浏览应用', route: '/tabs/apps' },
  { emoji: '⭐', title: '管理收藏', desc: '登录后可收藏喜欢的应用，在"我的应用"中快速访问', action: '我的应用', route: '/workshop' },
  { emoji: '🎨', title: '个性设置', desc: '自定义主题、深色模式等，打造专属体验', action: '去设置', route: '/user/settings' },
]
const showGuide = ref(false)
const currentStep = ref(0)

const isFirst = computed(() => currentStep.value === 0)
const isLast = computed(() => currentStep.value === guideSteps.length - 1)

function goToStep(route: string) {
  router.push(route)
}

/**
 * 常见问题
 */
const faqList = [
  { q: '云乐坊是什么？', a: '云乐坊是一个应用聚合平台，汇集各类实用小工具，无需下载即可直接使用。' },
  { q: '需要注册才能使用吗？', a: '大部分应用无需登录即可使用。登录后可以收藏应用、同步数据等。' },
  { q: '如何收藏应用？', a: '登录后，在应用详情页点击收藏按钮，即可将应用添加到"我的应用"中。' },
  { q: '支持哪些登录方式？', a: '目前支持手机号、微信等多种登录方式。' },
  { q: '如何切换深色模式？', a: '进入"设置"页面，在"外观"选项中可以切换浅色/深色/跟随系统。' },
  { q: '遇到问题如何反馈？', a: '返回"我的"页面，点击"反馈"可通过邮件或微信客服联系我们。' },
]
const showFaq = ref(false)
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" text="我" />
        </IonButtons>
        <IonTitle>帮助</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true">
      <IonHeader collapse="condense">
        <IonToolbar>
          <IonTitle size="large">
            帮助
          </IonTitle>
        </IonToolbar>
      </IonHeader>

      <!-- 帮助 -->
      <k-block-title>帮助</k-block-title>
      <k-list strong inset>
        <k-list-item
          link
          title="新手引导"
          after="了解基本操作"
          @click="showGuide = !showGuide"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-purple">
              <IonIcon :icon="compassOutline" />
            </span>
          </template>
        </k-list-item>

        <k-list-item
          link
          title="常见问题"
          after="FAQ"
          @click="showFaq = !showFaq"
        >
          <template #media>
            <span class="ios-icon-box ios-icon-blue">
              <IonIcon :icon="bookOutline" />
            </span>
          </template>
        </k-list-item>
      </k-list>

      <!-- 新手引导内容 -->
      <Transition name="guide">
        <k-block v-if="showGuide" strong inset class="mt-0!">
          <!-- 步骤分段控件 -->
          <IonSegment
            :value="String(currentStep)"
            mode="ios"
            @ion-change="(e: CustomEvent) => currentStep = Number(e.detail.value)"
          >
            <IonSegmentButton
              v-for="(step, idx) in guideSteps"
              :key="idx"
              :value="String(idx)"
            >
              <IonLabel>{{ step.emoji }}</IonLabel>
            </IonSegmentButton>
          </IonSegment>

          <!-- 当前步骤内容 -->
          <div class="mt-5 text-center">
            <Transition name="step" mode="out-in">
              <div :key="currentStep">
                <p class="text-base font-semibold">
                  {{ guideSteps[currentStep]!.title }}
                </p>
                <p class="mx-auto mt-2 max-w-64 text-sm ios-secondary-text">
                  {{ guideSteps[currentStep]!.desc }}
                </p>
                <div class="mt-4">
                  <k-button rounded inline @click="goToStep(guideSteps[currentStep]!.route)">
                    {{ guideSteps[currentStep]!.action }}
                  </k-button>
                </div>
              </div>
            </Transition>
          </div>

          <!-- 上一步 / 下一步 -->
          <div class="mt-5 flex items-center justify-between">
            <k-button
              clear
              inline
              rounded
              :disabled="isFirst"
              @click="currentStep--"
            >
              <IonIcon :icon="chevronBackOutline" class="mr-1 text-sm" />
              上一步
            </k-button>
            <span class="text-xs ios-secondary-text">{{ currentStep + 1 }} / {{ guideSteps.length }}</span>
            <k-button
              clear
              inline
              rounded
              :disabled="isLast"
              @click="currentStep++"
            >
              下一步
              <IonIcon :icon="chevronForwardOutline" class="ml-1 text-sm" />
            </k-button>
          </div>
        </k-block>
      </Transition>

      <!-- 常见问题内容 -->
      <Transition name="guide">
        <k-block v-if="showFaq" strong inset class="mt-4">
          <div class="space-y-4">
            <div
              v-for="(item, idx) in faqList"
              :key="idx"
            >
              <p class="text-sm font-medium">
                {{ item.q }}
              </p>
              <p class="mt-1 text-xs ios-secondary-text">
                {{ item.a }}
              </p>
            </div>
          </div>
        </k-block>
      </Transition>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.guide-enter-active,
.guide-leave-active {
  transition: all 0.3s ease;
  overflow: hidden;
}
.guide-enter-from,
.guide-leave-to {
  opacity: 0;
  max-height: 0;
}
.guide-enter-to,
.guide-leave-from {
  opacity: 1;
  max-height: 500px;
}

.step-enter-active,
.step-leave-active {
  transition: all 0.25s ease;
}
.step-enter-from {
  opacity: 0;
  transform: translateX(20px);
}
.step-leave-to {
  opacity: 0;
  transform: translateX(-20px);
}
</style>
