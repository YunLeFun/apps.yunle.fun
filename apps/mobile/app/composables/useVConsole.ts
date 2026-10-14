import consola from 'consola'

let vConsoleInstance: any = null
const active = ref(false)

/**
 * vConsole 按需加载管理
 * 仅在开发者模式下动态导入，不影响普通用户包体积
 */
export function useVConsole() {
  const developerStore = useDeveloperStore()

  async function show() {
    try {
      if (!vConsoleInstance) {
        const { default: VConsole } = await import('vconsole')
        vConsoleInstance = new VConsole({
          theme: document.documentElement.classList.contains('ion-palette-dark') ? 'dark' : 'light',
          pluginOrder: ['system', 'network', 'element', 'storage'],
        })
        consola.info('[Developer] vConsole 已加载')
      }

      vConsoleInstance.show()
      active.value = true
    }
    catch (e) {
      consola.error('[Developer] vConsole 加载失败:', e)
    }
  }

  function destroy() {
    if (vConsoleInstance) {
      vConsoleInstance.destroy()
      vConsoleInstance = null
      active.value = false
      consola.info('[Developer] vConsole 已销毁')
    }
  }

  function toggle() {
    if (active.value) {
      destroy()
    }
    else {
      show()
    }
  }

  // 退出开发者模式时自动销毁
  watch(() => developerStore.enabled, (val) => {
    if (!val) {
      destroy()
    }
  })

  return {
    active,
    show,
    toggle,
    destroy,
  }
}
