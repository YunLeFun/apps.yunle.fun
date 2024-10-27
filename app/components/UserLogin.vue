<script lang="ts" setup>
// const email = ref('')
import consola from 'consola'

const appInfo = computed(() => {
  return {
    id: 'cook',
    name: '食用手册',
    url: 'https://cook.yunyoujun.cn',
  }
})

function loginByWechat() {
  consola.info('通过微信登录')

  window.location.href = generateUserAuthLink({
    scope: 'snsapi_userinfo',
  })
}
</script>

<template>
  <div
    class="w-full flex items-center justify-center"
    m="auto"
    max-w-xs
  >
    <div
      class="border rounded-xl bg-white p-5 shadow dark:border-dark dark:bg-dark"
      gap="5"
      w="full"
      flex="~ col"
    >
      <div class="flex flex-col">
        <h3 class="items-center justify-center gap-1 text-sm op-80" flex="~">
          <!-- <div i-ri-fingerprint-line /> -->
          正在为应用
          <a :href="appInfo.url" target="_blank" class="text-blue-500 dark:text-blue-400">
            {{ appInfo.name }} ({{ appInfo.id }})
          </a>
          登录
        </h3>
      </div>

      <div class="flex items-center">
        <button
          class="focus-visible:ring-ring h-9 w-full inline-flex items-center justify-center rounded-md bg-#07c160 px-4 py-2 text-sm text-white font-medium shadow transition-colors disabled:pointer-events-none hover:bg-green-600 disabled:opacity-50 focus-visible:outline-none focus-visible:ring-1"
          gap="2"
          @click="loginByWechat"
        >
          <div i-ri-wechat-fill />
          <span>微信登录</span>
        </button>
      </div>
    </div>
  </div>
</template>
