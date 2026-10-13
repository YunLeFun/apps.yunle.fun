<script setup lang="ts">
const { state, error, available, openApp, refreshCatalog, command } = useDesktop()
const colorMode = useColorMode()
watch(() => colorMode.preference, (preference) => {
  if (preference === 'system' || preference === 'light' || preference === 'dark')
    void window.desktop?.setTheme(preference).catch(() => undefined)
})
</script>

<template>
  <main class="desktop">
    <CatalogSidebar :catalog="state?.catalog" :available="available" :active-app-id="state?.guest.appId" @open="openApp" @refresh="refreshCatalog" />
    <section class="workspace" aria-label="应用工作区">
      <GuestToolbar :guest="state?.guest" @command="command" />
      <p v-if="error" role="alert" class="error">
        {{ error }}
      </p>
      <p v-if="state?.guest.error" role="alert" class="error">
        {{ state.guest.error }}
      </p>
      <AppViewport :open="state?.guest.open || false" />
      <footer class="workspace-footer">
        <span>{{ available ? '云乐坊桌面端' : '请在桌面客户端中使用应用' }}</span>
        <label class="appearance-control">
          外观
          <select v-model="colorMode.preference" aria-label="外观">
            <option value="system">跟随系统</option>
            <option value="light">浅色</option>
            <option value="dark">深色</option>
          </select>
        </label>
      </footer>
    </section>
  </main>
</template>
