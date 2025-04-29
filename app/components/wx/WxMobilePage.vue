<script setup lang="ts">
// 微信基础页面

defineProps<{
  type: 'success' | 'warn' | 'info' | 'custom'
}>()
</script>

<template>
  <div class="weui-msg w-full">
    <div class="weui-msg__icon-area items-center justify-center gap-2 pt-4" flex="~ col">
      <YlfLogoSvg v-if="type === 'custom'" />
      <i
        v-if="type === 'success'"
        class="weui-icon-success weui-icon_msg"
      />
      <i
        v-if="type === 'warn'"
        class="weui-icon_msg weui-icon-warn"
      />
      <i
        v-if="type === 'info'"
        class="weui-icon_msg weui-icon-info"
      />
    </div>
    <div class="weui-msg__text-area">
      <div
        v-if="type !== 'custom'"
        flex="~" class="mb-4 items-center justify-center gap-1"
      >
        <YlfLogoSvg class="size-6" />
        <span>
          云乐坊
        </span>
      </div>

      <h2 class="weui-msg__title">
        <slot name="title" />
      </h2>

      <p class="weui-msg__desc">
        <slot name="desc" />
      </p>
    </div>

    <div class="weui-msg__opr-area">
      <p class="weui-btn-area">
        <slot name="actions" />
      </p>
    </div>
  </div>
</template>
