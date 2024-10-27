<script lang="ts" setup>
import type { BottomMenuItem } from '@yunlefun/vue'

const items: BottomMenuItem[] = [
  {
    icon: 'i-ri-home-line',
    activeIcon: 'i-ri-home-fill',
    title: '首页',
    to: '/',
  },
  {
    icon: 'i-ri-compass-2-line',
    activeIcon: 'i-ri-compass-2-fill',
    title: '发现',
    to: '/discover',
  },
  {
    icon: 'i-ri-user-line',
    activeIcon: 'i-ri-user-fill',
    title: '我的',
    to: '/user',
  },
]

const router = useRouter()
// not ref for ssr
const active = useState('/')
function onClick(item: BottomMenuItem) {
  if (!item.to || item.to === active.value)
    return

  active.value = item.to || ''
  router.push(item.to)
}
</script>

<template>
  <YlfBottomMenu shadow>
    <YlfBottomMenuItem
      v-for="item in items"
      :key="item.to"
      :item="item"
      :active="active === item.to"
      @click="onClick"
    />
  </YlfBottomMenu>
</template>
