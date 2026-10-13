/**
 * 从 App 启动开始捕获自身 WebView 控制台日志。
 * 日志会先脱敏，再写入有上限和有效期的本地环形缓冲区。
 */
export default defineNuxtPlugin(() => {
  useConsoleStore().startCapture()
  console.info('[Diagnostics] local log capture started') // eslint-disable-line no-console
})
