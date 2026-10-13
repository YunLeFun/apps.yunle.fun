<script setup lang="ts">
import { useWxLogin } from '~/composables/wx/useWxLogin'

const toast = useToast()

const router = useRouter()

const {
  loadAndCheckQrcode,
  wxLoginConfirmQrcode,
  qrcodeStatus,
} = useWxLogin({
  onSuccess: async () => {
    // 登录成功后跳转到重定向页面 或 首页
    setTimeout(() => {
      router.push('/user')
    }, 1200)

    toast.showSuccess('登录成功')
  },
})

onMounted(async () => {
  // 轮询 check login qrcode
  await loadAndCheckQrcode()
})
</script>

<template>
  <div class="mt-20 flex items-center justify-center p-4">
    <!-- <div id="login_container" /> -->

    <div class="items-center justify-center flex flex-col">
      <h3 class="my-2 text-base font-bold">
        微信扫码登录
      </h3>

      <QrcodeContainer
        :qrcode-url="wxLoginConfirmQrcode"
        :status="qrcodeStatus"
        :error="{
          title: '登录失败',
          tip: '请重新扫码登录',
        }"
        @reload="loadAndCheckQrcode"
      />
    </div>
  </div>
</template>
