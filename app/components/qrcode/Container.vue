<script lang="ts" setup>
import type { QrcodeStatus } from '~/composables/wx/useWxLogin'

interface TitleAndTip {
  /**
   * 标题
   */
  title?: string
  /**
   * 提示
   */
  tip?: string
}

const props = withDefaults(defineProps<{
  /**
   * 二维码图片地址
   */
  qrcodeUrl: string
  /**
   * 二维码状态
   */
  status?: QrcodeStatus

  success?: TitleAndTip
  normal?: TitleAndTip
  expired?: TitleAndTip
  error?: TitleAndTip
}>(), {
  expired: () => ({
    title: '二维码过期，请刷新重试',
    tip: '二维码每 5 分钟更新',
  }),
  fail: () => ({
    title: '',
    tip: '',
  }),
})

const emit = defineEmits(['reload'])

const tip = computed(() => {
  switch (props.status) {
    case 'success':
      return props.success?.tip
    case 'normal':
      return props.normal?.tip
    case 'expired':
      return props.expired?.tip
    case 'error':
      return props.error?.tip
    default:
      return ''
  }
})

const title = computed(() => {
  switch (props.status) {
    case 'success':
      return props.success?.title
    case 'normal':
      return props.normal?.title
    case 'expired':
      return props.expired?.title
    case 'error':
      return props.error?.title
    default:
      return ''
  }
})

/**
 * 重载二维码
 */
function reloadQrcode() {
  emit('reload')
}
</script>

<template>
  <div class="qrcode-wrap items-center justify-center p-2 flex flex-col">
    <div
      class="qrcode relative rounded bg-white"
      :class="{ showMask: status !== 'normal', border: !qrcodeUrl }"
    >
      <img
        v-if="qrcodeUrl" class="h-full w-full"
        :src="qrcodeUrl"
      >
      <div
        class="mask absolute h-full w-full cursor-pointer items-center justify-center bg-white/95 text-5xl flex"
        @click="reloadQrcode"
      >
        <div v-if="status === 'success'" class="text-green-500 i-ri-checkbox-circle-fill" />
        <div
          v-else
          class="i-ri-refresh-line transform text-black duration-800"
          :class="{
            'rotate-180': status !== 'normal',
          }"
        />
      </div>
    </div>
    <Transition appear>
      <div v-if="title || tip">
        <div
          v-if="title"
          class="title mt-2 items-center justify-center gap-1 text-sm flex"
        >
          <div v-if="status === 'error'" class="i-ri-error-warning-fill text-yellow-500" />
          <span class="opacity-80" v-html="title" />
        </div>
        <div
          v-if="tip"
          class="tip mt-2 text-xs opacity-50"
          v-html="tip"
        />
      </div>
    </Transition>
  </div>
</template>

<style lang="scss">
.qrcode-wrap {
  .qrcode {
    width: var(--qrcode-size, 250px);
    height: var(--qrcode-size, 250px);
    overflow: hidden;

    .mask {
      position: absolute;
      left: 0;
      top: 0;
      transition: opacity 0.3s ease-in-out;
      opacity: 0;
    }

    &.showMask {
      .mask {
        opacity: 1;
      }
    }
  }
}
</style>
