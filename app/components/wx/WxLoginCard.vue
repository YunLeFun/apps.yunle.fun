<script setup lang="ts">
import { isPlatform } from '@ionic/vue'
import { createEmbeddedWxLogin, generateQrconnectUrl } from '~~/packages/auth/src'

const config = useRuntimeConfig()

const inMobile = computed(() => {
  return isPlatform('hybrid') || isPlatform('mobile') || isPlatform('tablet') || isPlatform('mobileweb')
})

/**
 * 内嵌微信登录 iframe 加载完毕
 */
const isIframeReady = ref(false)
/**
 * 初始化内嵌微信登录
 */
function initWxLoginInIframe() {
  const { init } = createEmbeddedWxLogin()
  const appId = config.public.wxOpenAppId
  init({
    self_redirect: false,
    id: 'wx_login_container',
    // appid: '',
    /**
     * https://open.weixin.qq.com/
     * me@yunyoujun.cn
     */
    appid: appId,
    /**
     * api oauth
     * passport-wechat
     */
    redirect_uri: config.public.wxOpenRedirectUri,
    scope: 'snsapi_login',
    /**
     * 新样式
     */
    stylelite: 1,
    color_scheme: 'auto',
    onReady() {
      isIframeReady.value = true
    },
  })
}

/**
 * 前往微信登录页面
 * @see https://developers.weixin.qq.com/doc/oplatform/Website_App/WeChat_Login/Wechat_Login.html
 */
function goToWxLoginPage() {
  const url = generateQrconnectUrl({
    appid: config.public.wxOpenAppId,
    redirectUri: config.public.wxOpenRedirectUri,
  })
  window.open(url, '_blank')
}

onMounted(() => {
  if (!inMobile.value) {
    initWxLoginInIframe()
  }
  else {
    //
  }
})
</script>

<template>
  <!-- 微信登录 -->
  <div class="flex flex-col items-center justify-center gap-4">
    <template v-if="!inMobile">
      <ion-chip>
        <ion-icon :icon="ioniconsLogoWechat" color="success" />
        <ion-label>微信登录</ion-label>
      </ion-chip>

      <div
        id="wx_login_container" alt="微信登录" :class="{
          hidden: !isIframeReady,
        }"
      />
      <div v-if="!isIframeReady" class="flex flex-col items-center justify-center gap-2">
        <ion-spinner name="dots" />
        <ion-text color="medium">
          正在加载
        </ion-text>
      </div>
    </template>

    <div v-else @click="goToWxLoginPage">
      <ion-chip color="success">
        <ion-icon :icon="ioniconsLogoWechat" color="success" />
        <ion-label>前往微信登录</ion-label>
      </ion-chip>
    </div>
  </div>
</template>

<style>
#wx_login_container {
  height: 100%;
}
</style>
