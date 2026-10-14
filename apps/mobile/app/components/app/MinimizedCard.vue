<script setup lang="ts">
const { sessions, minimizedKey, resume, end, refresh } = useBackgroundSessions()
const session = computed(() => sessions.value.find(s => s.key === minimizedKey.value))
const settings = useSettingsStore()
const pending = ref(false)

async function act(action: 'resume' | 'end') {
  if (!session.value || pending.value)
    return
  pending.value = true
  try {
    await (action === 'resume' ? resume(session.value) : end(session.value))
  }
  catch {
    useToast().showError(action === 'resume' ? '暂时无法恢复应用，请从应用列表重新打开' : '暂时无法结束应用，请重试')
    await refresh()
  }
  finally {
    pending.value = false
  }
}
</script>

<template>
  <AppMinimizedCardView
    v-if="session && settings.inAppBrowserMode !== 'system'"
    :name="session.name"
    :size="settings.previewWindowSize"
    :preview-image="session.previewImage"
    :logo="session.logo"
    :emoji="session.emoji"
    :pending="pending"
    @resume="act('resume')"
    @end="act('end')"
  />
</template>
