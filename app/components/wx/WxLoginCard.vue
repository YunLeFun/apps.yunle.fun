<!-- eslint-disable no-alert -->
<script setup lang="ts">
import { Capacitor } from '@capacitor/core'
import { isPlatform } from '@ionic/vue'
import { consola } from 'consola'
import { createEmbeddedWxLogin } from '~~/packages/auth/src'

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
 *
 * @todo
 * 第三方浏览器移动端网页无法拉起微信登录，只能在微信内打开
 * 添加复制到微信内打开的提示
 */
function goToWxLogin() {
  // const url = generateQrconnectUrl({
  //   appid: config.public.wxOpenAppId,
  //   redirectUri: config.public.wxOpenRedirectUri,
  // })
  // window.open(url, '_blank')

  const isNativePlatform = Capacitor.isNativePlatform()
  consola.info('isNativePlatform', isNativePlatform)
  if (isNativePlatform) {
    // TODO
    Wechat.auth('snsapi_userinfo', `_${new Date()}`, (res: any) => {
      alert(JSON.stringify(res))
    }, (reason: any) => {
      alert(`Failed: ${reason}`)
    })
  }
  else {
    const url = generateUserAuthLink({
      appid: config.public.wxOpenAppId,
    })
    window.open(url, '_blank')
  }
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

    <button
      v-else
      class="wx-login-btn"
      @click="goToWxLogin"
    >
      <ion-icon :icon="ioniconsLogoWechat" class="text-xl" />
      <span>微信登录</span>
    </button>
  </div>
</template>

<style scoped>
#wx_login_container {
  height: 100%;
}

.wx-login-btn {
  /* 布局 */
  @apply flex items-center justify-center gap-2;
  @apply w-full px-5 py-2;

  /* 微信品牌色 */
  @apply bg-[#07c160] text-white;

  /* 圆角 */
  @apply rounded-lg;

  /* 字体 */
  @apply text-base font-medium;

  /* 阴影 */
  @apply shadow-sm;

  /* 交互效果 */
  @apply active:scale-98 active:bg-[#06ad56];
  @apply transition-all duration-150;

  /* 禁用默认样式 */
  @apply border-none outline-none;
  @apply cursor-pointer;
}

/* hover 效果（非触屏设备） */
@media (hover: hover) {
  .wx-login-btn:hover {
    @apply bg-[#06ad56] shadow-md;
  }
}
</style>
