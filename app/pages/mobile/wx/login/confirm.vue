<script setup lang="ts">
import { isInWxBrowser } from '@yunlefun/toolkit'
import consola from 'consola'

const route = useRoute()

// 移动端 扫码确认登录
useHead({
  title: '微信登录确认 - 云乐坊',
  meta: [
    {
      name: 'viewport',
      content: 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=0',
    },
  ],
  link: [
    {
      rel: 'stylesheet',
      href: 'https://res.wx.qq.com/t/wx_fed/weui-source/res/2.6.16/weui.min.css',
    },
  ],
})

definePageMeta({
  layout: 'fullscreen',
})

const pageStatus = ref<'' | 'canceled' | 'confirmed' | 'notInWx'>('')

onMounted(() => {
  if (!isInWxBrowser() && !import.meta.env.DEV) {
    // 不在微信浏览器中，提示用户使用微信浏览器
    pageStatus.value = 'notInWx'
    return
  }

  const code = route.query.code as string
  const state = route.query.state as string
  if (code && state) {
    // 发送 code 给后端，结束登录流程

    // 通过微信授权登录
    pageStatus.value = 'confirmed'
  }
  else {
    // 扫码成功
  }
})

/**
 * 确认登录
 */
function confirm() {
  window.location.href = generateUserAuthLink({
    scope: 'snsapi_userinfo',
    redirect_uri: window.location.href,
  })
}

/**
 * 取消登录
 */
function cancel() {
  consola.info('canceled')
  pageStatus.value = 'canceled'
}

const title = computed(() => {
  switch (pageStatus.value) {
    case 'notInWx':
      return '无法授权登录'
    case 'canceled':
      return '登录已取消'
    case 'confirmed':
      return '登录已确认'
  }
  return '授权登录'
})

const desc = computed(() => {
  switch (pageStatus.value) {
    case 'notInWx':
      return '请使用微信打开此链接'
    case 'canceled':
      return ''
    case 'confirmed':
      return ''
  }
  return '确认使用此微信号登录云乐坊'
})

const type = computed(() => {
  switch (pageStatus.value) {
    case 'notInWx':
      return 'warn'
    case 'canceled':
      return 'info'
    case 'confirmed':
      return 'success'
  }
  return 'custom'
})
</script>

<template>
  <WxMobilePage :type="type">
    <template #title>
      {{ title }}
    </template>

    <template #desc>
      {{ desc }}
    </template>

    <template v-if="!pageStatus" #actions>
      <button
        id="submitButton"
        class="weui-btn weui-btn_primary"
        @click="confirm"
      >
        确认
      </button>
      <button
        id="cancelButton"
        class="weui-btn weui-btn_default"
        @click="cancel"
      >
        取消
      </button>
    </template>
  </WxMobilePage>
</template>
