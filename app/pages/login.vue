<script lang="ts" setup>
import type { WxUserInfo } from '../utils'

definePageMeta({
  // layout: 'fullscreen',
})

const route = useRoute()

/**
 * 微信授权状态
 */
const wxAuthState = ref<'' | 'success' | 'error'>('')
const wxUserInfo = ref<WxUserInfo>()

const errorInfo = ref('')

const { $api } = useNuxtApp()

onMounted(async () => {
  const { code, state } = route.query
  if (code && state) {
    // 授权重定向成功

    // 1. 发送 code 给 api.yunle.fun 获取用户信息
    const res = await $api<{
      success: boolean
      msg: string
      data: WxUserInfo
    }>('https://api.yunle.fun/wx/auth', {
      method: 'GET',
      query: {
        code,
      },
    })

    if (res.success) {
      wxAuthState.value = 'success'
      wxUserInfo.value = res.data
    }
    else {
      wxAuthState.value = 'error'
      // consola.error(res.msg)
      errorInfo.value = res.msg
    }
  }
})
</script>

<template>
  <div class="w-full items-center pt-25" flex="~ col">
    <Logo mb-8 />
    <UserLogin />

    <br>
    <WxUserInfo
      v-if="wxAuthState === 'success'"
      :user-info="wxUserInfo"
    />
    <div v-if="wxAuthState === 'error'" class="text-red-500">
      授权失败: {{ errorInfo }}
    </div>
  </div>
</template>
