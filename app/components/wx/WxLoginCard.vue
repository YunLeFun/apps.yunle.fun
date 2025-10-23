<script setup lang="ts">
import { createEmbeddedWxLogin } from '~~/packages/auth/src'

const config = useRuntimeConfig()

onMounted(() => {
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
  })
})
</script>

<template>
  <!-- 微信登录 -->
  <div class="flex flex-col items-center justify-center gap-4">
    <ion-chip>
      <ion-icon :icon="ioniconsLogoWechat" color="success" />
      <ion-label>微信登录</ion-label>
    </ion-chip>

    <div id="wx_login_container" alt="微信登录" />
  </div>
</template>

<style>
#wx_login_container {
  height: 100%;
}
</style>
