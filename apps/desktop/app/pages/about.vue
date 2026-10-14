<script setup lang="ts">
const { state, available } = useDesktop()
</script>

<template>
  <main class="about-page">
    <div class="about-titlebar" aria-hidden="true" />
    <section class="about">
      <NuxtLink class="text-link" to="/">
        返回应用目录
      </NuxtLink>
      <br>
      <img class="about-brand" src="/pwa-192x192.png" alt="云乐坊" width="80" height="80">
      <h1>关于云乐坊桌面端</h1>
      <p>在桌面上发现和使用云应用。应用目录与 Web、移动端共享，应用在各自独立的浏览空间中打开。</p>
      <p>当前版本支持公开免费应用。需要账号、会员、购买或邀请的应用，请继续在 Web 或移动端使用。</p>
      <p>桌面端账号授权和自动更新将在后续版本开放。</p>
      <RuntimeStatus :state="state" :available="available" />
    </section>
  </main>
</template>
