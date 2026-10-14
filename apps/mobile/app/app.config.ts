export default defineAppConfig({
  icon: {
    // 默认使用 CSS 模式，性能更优
    mode: 'css',
    // TailwindCSS v4 需要指定 cssLayer
    cssLayer: 'base',
    size: '1em',
  },
})
