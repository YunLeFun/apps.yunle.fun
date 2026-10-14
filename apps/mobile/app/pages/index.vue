<script setup lang="ts">
// 应用入口默认重定向到云居首页。
// 用真重定向（而非把首页 alias 到 /），让 pathname 为 /tabs/home，
// 底部 IonTabBar 才能正确点亮云居 tab。
definePageMeta({
  redirect: '/tabs/home',
})
</script>
