import { computed, onUnmounted, ref } from 'vue'

/**
 * 通用倒计时 composable
 * 用于 OTP 验证码发送后的冷却倒计时
 */
export function useCountdown(seconds = 60) {
  const remaining = ref(0)
  let timer: ReturnType<typeof setInterval> | null = null

  const isActive = computed(() => remaining.value > 0)

  function start() {
    stop()
    remaining.value = seconds
    timer = setInterval(() => {
      remaining.value--
      if (remaining.value <= 0)
        stop()
    }, 1000)
  }

  function stop() {
    if (timer) {
      clearInterval(timer)
      timer = null
    }
    remaining.value = 0
  }

  onUnmounted(stop)

  return { remaining, isActive, start, stop }
}
