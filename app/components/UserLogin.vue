<script lang="ts" setup>
// const email = ref('')
import consola from 'consola'

const appInfo = computed(() => {
  return {
    id: '2',
    color: 'orange',
    icon: 'https://cook.yunyoujun.cn/favicon.svg',
    name: '食用手册',
    code: 'cook',
    url: 'https://cook.yunyoujun.cn',
  }
})

function loginByWechat() {
  consola.info('通过微信登录')

  window.location.href = generateUserAuthLink({
    scope: 'snsapi_userinfo',
    redirect_uri: window.location.href,
  })
}
</script>

<template>
  <DarkToggle class="absolute right-4 top-4" />

  <div
    class="w-full flex items-center justify-center"
    m="auto"
    max-w-xs
  >
    <div
      class="rounded-xl bg-white p-5 shadow dark:border-dark dark:bg-dark"
      gap="5"
      w="full"
      flex="~ col"
    >
      <div class="flex flex-col">
        <h3 class="items-center justify-center gap-4 text-sm" flex="~ col">
          <!-- <div i-ri-fingerprint-line /> -->
          <span class="op-60">
            正在为以下应用登录
          </span>
          <a
            :href="appInfo.url" target="_blank"
            class="inline-flex items-center justify-center gap-1 rounded-full text-sm text-blue-500 dark:text-blue-400"
          >
            <div
              v-if="appInfo.icon"
              class="size-5 inline-flex items-center justify-center rounded-full p-1"
              :style="{ backgroundColor: appInfo.color }"
            >
              <img
                :src="appInfo.icon" alt="icon"
                class="inline-block"
              >
            </div>
            <span font="bold">
              {{ appInfo.name }} ({{ appInfo.id }})
            </span>
          </a>
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
