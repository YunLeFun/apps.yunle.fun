/**
 * 主题初始化插件
 * 确保应用启动时正确应用保存的主题设置
 */
export default defineNuxtPlugin(() => {
  const settingsStore = useSettingsStore()

  // 初始化主题
  settingsStore.initTheme()
})
