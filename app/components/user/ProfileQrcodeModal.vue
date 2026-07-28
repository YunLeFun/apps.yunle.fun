<script setup lang="ts">
import { kButton } from 'konsta/vue'
import QRCode from 'qrcode'

const props = defineProps<{
  open: boolean
  presentingElement?: HTMLElement
  nickname: string
  description?: string
  avatar?: string
  avatarInitial: string
  userId?: string
}>()

const emit = defineEmits<{
  'update:open': [val: boolean]
}>()

const qrcodeDataUrl = ref('')
const canvasRef = ref<HTMLCanvasElement>()
const { resolvedSrc: resolvedAvatar } = useAvatarUrl(() => props.avatar)

const profileUrl = computed(() => {
  if (!props.userId)
    return ''
  return `https://www.yunle.fun/user/${props.userId}`
})

watch(() => props.open, async (val) => {
  if (val && profileUrl.value) {
    try {
      qrcodeDataUrl.value = await QRCode.toDataURL(profileUrl.value, {
        width: 200,
        margin: 2,
        color: {
          dark: '#000000',
          light: '#ffffff',
        },
      })
    }
    catch {
      qrcodeDataUrl.value = ''
    }
  }
})

/**
 * 保存名片为图片
 */
async function saveCard() {
  if (!canvasRef.value)
    return

  const canvas = canvasRef.value
  const ctx = canvas.getContext('2d')
  if (!ctx)
    return

  const width = 340
  const height = 440
  const dpr = 2
  canvas.width = width * dpr
  canvas.height = height * dpr
  ctx.scale(dpr, dpr)

  // 背景
  ctx.fillStyle = '#ffffff'
  ctx.beginPath()
  ctx.roundRect(0, 0, width, height, 16)
  ctx.fill()

  // 头像区域
  ctx.save()
  ctx.beginPath()
  ctx.arc(width / 2, 60, 32, 0, Math.PI * 2)
  ctx.clip()
  if (resolvedAvatar.value) {
    const img = new Image()
    img.crossOrigin = 'anonymous'
    img.src = resolvedAvatar.value
    try {
      await new Promise<void>((resolve, reject) => {
        img.onload = () => resolve()
        img.onerror = () => reject(new Error('名片头像加载失败'))
      })
      ctx.drawImage(img, width / 2 - 32, 28, 64, 64)
    }
    catch {
      ctx.fillStyle = '#007aff'
      ctx.fill()
      ctx.fillStyle = '#ffffff'
      ctx.font = 'bold 24px -apple-system, BlinkMacSystemFont, sans-serif'
      ctx.textAlign = 'center'
      ctx.textBaseline = 'middle'
      ctx.fillText(props.avatarInitial, width / 2, 60)
    }
  }
  else {
    ctx.fillStyle = '#007aff'
    ctx.fill()
    ctx.fillStyle = '#ffffff'
    ctx.font = 'bold 24px -apple-system, BlinkMacSystemFont, sans-serif'
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'
    ctx.fillText(props.avatarInitial, width / 2, 60)
  }
  ctx.restore()

  // 昵称
  ctx.fillStyle = '#1c1c1e'
  ctx.font = 'bold 18px -apple-system, BlinkMacSystemFont, sans-serif'
  ctx.textAlign = 'center'
  ctx.fillText(props.nickname, width / 2, 115)

  // 简介
  if (props.description) {
    ctx.fillStyle = '#8e8e93'
    ctx.font = '13px -apple-system, BlinkMacSystemFont, sans-serif'
    ctx.fillText(props.description.slice(0, 30), width / 2, 138)
  }

  // 二维码
  if (qrcodeDataUrl.value) {
    const qrImg = new Image()
    qrImg.src = qrcodeDataUrl.value
    await new Promise(resolve => qrImg.onload = resolve)
    const qrSize = 180
    ctx.drawImage(qrImg, (width - qrSize) / 2, 160, qrSize, qrSize)
  }

  // 底部提示
  ctx.fillStyle = '#8e8e93'
  ctx.font = '11px -apple-system, BlinkMacSystemFont, sans-serif'
  ctx.textAlign = 'center'
  ctx.fillText('扫码查看个人主页', width / 2, 370)
  ctx.fillText('云乐坊 yunle.fun', width / 2, 390)

  // 下载
  const link = document.createElement('a')
  link.download = `${props.nickname}-名片.png`
  link.href = canvas.toDataURL('image/png')
  link.click()
}

function close() {
  emit('update:open', false)
}
</script>

<template>
  <IonModal :is-open="open" :presenting-element="presentingElement" @did-dismiss="close">
    <IonHeader>
      <IonToolbar>
        <IonButtons slot="start">
          <IonButton @click="close">
            关闭
          </IonButton>
        </IonButtons>
        <IonTitle>我的名片</IonTitle>
        <IonButtons slot="end">
          <IonButton :strong="true" @click="saveCard">
            保存
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>

    <IonContent class="ion-padding">
      <div class="flex flex-col items-center pt-4">
        <!-- 名片预览卡 -->
        <div class="w-72 overflow-hidden rounded-2xl bg-white shadow-lg dark:bg-zinc-800">
          <div class="flex flex-col items-center px-6 py-8">
            <!-- 头像 -->
            <div class="mb-3 h-16 w-16 overflow-hidden rounded-full">
              <UserAvatar
                :src="avatar"
                :alt="nickname"
                telemetry-surface="user.profile-card"
                class="h-full w-full object-cover"
              >
                <template #fallback>
                  <div class="h-full w-full flex items-center justify-center ios-avatar-bg">
                    <span class="text-xl font-semibold text-white">{{ avatarInitial }}</span>
                  </div>
                </template>
              </UserAvatar>
            </div>

            <!-- 昵称 -->
            <h3 class="text-lg font-bold">
              {{ nickname }}
            </h3>
            <p v-if="description" class="mt-1 text-center text-xs ios-secondary-text line-clamp-2">
              {{ description }}
            </p>

            <!-- 二维码 -->
            <div class="mt-4 rounded-xl bg-white p-3">
              <img
                v-if="qrcodeDataUrl"
                :src="qrcodeDataUrl"
                alt="QR Code"
                class="h-44 w-44"
              >
              <div v-else class="h-44 w-44 flex items-center justify-center">
                <IonSpinner />
              </div>
            </div>

            <!-- 提示 -->
            <p class="mt-3 text-xs ios-secondary-text">
              扫码查看个人主页
            </p>
          </div>

          <!-- 底部品牌 -->
          <div class="border-t border-gray-100 px-6 py-3 dark:border-zinc-700">
            <p class="text-center text-xs ios-secondary-text">
              云乐坊 yunle.fun
            </p>
          </div>
        </div>

        <!-- 保存按钮 -->
        <div class="mt-6 w-full px-4">
          <k-button large class="w-full" @click="saveCard">
            保存名片图片
          </k-button>
        </div>
      </div>

      <!-- 隐藏 Canvas 用于生成图片 -->
      <canvas ref="canvasRef" class="hidden" />
    </IonContent>
  </IonModal>
</template>
