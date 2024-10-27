<script setup lang="ts">
import { config } from '../../config'

/**
 * https://open.weixin.qq.com/
 * 需要资质认证 暂时不加
 * @see https://developers.weixin.qq.com/doc/oplatform/Website_App/WeChat_Login/Wechat_Login.html
 */
// 将微信登录二维码内嵌到自己页面

useScriptTag('http://res.wx.qq.com/connect/zh_CN/htmledition/js/wxLogin.js', () => {
  // @ts-expect-error wxLogin
  const obj = new window.WxLogin({
    self_redirect: true,
    id: 'login_container',
    appid: config.wx.appId,
    scope: 'snsapi_login',
    redirect_uri: config.wx.redirectUri,
    state: '',
    style: '',
    href: '',
    // 切换二维码登录样式，值为1时二维码登录将切换到新样式。详见文档底部FAQ。
    stylelite: 1,
    // 启用或禁用快速登录功能，值为0时将禁用快速登录，如发现参数不生效可检查redirect_uri是否已经正确encode。
    // fast_login:
  })
})
</script>

<template>
  <div class="mt-20 flex items-center justify-center p-4">
    <div id="login_container" />
  </div>
</template>
