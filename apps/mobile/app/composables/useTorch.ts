/**
 * 摄像头手电筒（torch）控制 composable
 *
 * 基于 W3C MediaStreamTrack `applyConstraints({ advanced: [{ torch }] })` 标准 API，
 * 不依赖任何第三方库。
 *
 * 支持矩阵（2025-05）：
 *   - ✅ Chrome / Edge（Android、桌面）
 *   - ✅ Safari iOS 17.4+
 *   - ✅ Capacitor iOS WebView（基于 WKWebView，跟随 Safari）
 *   - ❌ Firefox（标准未实现）
 *   - ❌ 前置摄像头通常无 torch
 *
 * 用法：
 * ```ts
 * const stream = ref<MediaStream | null>(null)
 * const { isSupported, enabled, toggle } = useTorch(stream)
 * ```
 *
 * 注意：必须传入**已经在播放**的 stream，否则 capabilities 为空。
 */
export function useTorch(stream: Ref<MediaStream | null>) {
  const enabled = ref(false)
  const isSupported = ref(false)

  /** 获取当前 stream 的第一条 video track */
  function getTrack(): MediaStreamTrack | null {
    const tracks = stream.value?.getVideoTracks?.() || []
    return tracks[0] || null
  }

  /**
   * 检测当前设备/摄像头是否支持手电筒
   *
   * 必须在 stream 已经在 `play()` 之后调用，否则 getCapabilities 可能返回空对象
   */
  function check(): boolean {
    const track = getTrack()
    if (!track || typeof track.getCapabilities !== 'function') {
      isSupported.value = false
      return false
    }
    const caps = track.getCapabilities() as MediaTrackCapabilities & { torch?: boolean }
    isSupported.value = !!caps.torch
    return isSupported.value
  }

  /** 设置手电筒开关 */
  async function set(on: boolean): Promise<void> {
    const track = getTrack()
    if (!track)
      return
    if (!isSupported.value && !check())
      return

    try {
      await track.applyConstraints({
        advanced: [{ torch: on } as MediaTrackConstraintSet & { torch: boolean }],
      })
      enabled.value = on
    }
    catch (err) {
      console.warn('[useTorch] applyConstraints failed:', err)
      enabled.value = false
    }
  }

  /** 切换手电筒 */
  async function toggle(): Promise<void> {
    await set(!enabled.value)
  }

  /** stream 变更时重新检测能力并复位状态 */
  watch(stream, () => {
    enabled.value = false
    // 延迟一帧等待 track 就绪
    nextTick(() => {
      check()
    })
  }, { immediate: true })

  return {
    /** 当前设备是否支持 torch */
    isSupported: readonly(isSupported),
    /** 手电筒是否已开启 */
    enabled: readonly(enabled),
    /** 手动重新检测能力（适合在 video play 之后调用） */
    check,
    /** 显式设置开关 */
    set,
    /** 切换开关 */
    toggle,
  }
}
