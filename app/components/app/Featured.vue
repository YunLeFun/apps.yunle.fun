<script lang="ts" setup>
const props = withDefaults(defineProps<Props>(), { managed: false })

const router = useRouter()

interface Props {
  /** 是否由父组件提供数据（避免重复加载） */
  managed?: boolean
}
const { featuredApp, loadFeatured } = useDiscovery()

// 非 managed 模式下自行加载
if (!props.managed) {
  onMounted(() => loadFeatured())
}

function openAppDetail() {
  router.push(`/app/${featuredApp.value.id}`)
}

const todayDateStr = computed(() => {
  const date = new Date()
  const month = date.getMonth() + 1
  const day = date.getDate()
  return `${month}月${day}日`
})
</script>

<template>
  <div class="app-featured pb-4">
    <div class="mb-3 flex items-center justify-between px-0.5">
      <h2 class="section text-3xl font-bold">
        今日推荐
        <small class="opacity-55">
          {{ todayDateStr }}
        </small>
      </h2>
    </div>

    <div
      class="featured-card cursor-pointer"
      @click="openAppDetail"
    >
      <!-- 卡片主体 -->
      <div
        class="featured-body relative overflow-hidden"
        :style="{ '--app-color': featuredApp.themeColor }"
      >
        <!-- 背景渐变层 -->
        <div class="featured-bg" />

        <!-- 装饰圆形光晕 -->
        <div class="featured-orb featured-orb-1" />
        <div class="featured-orb featured-orb-2" />

        <!-- 内容区 -->
        <div class="featured-content">
          <!-- 顶部标签 -->
          <div class="featured-badge">
            <span class="featured-badge-dot" />
            {{ featuredApp.subtitle || '编辑精选' }}
          </div>

          <!-- 中部：图标 + 文字 -->
          <div class="featured-main">
            <!-- 应用图标 -->
            <div class="featured-icon-wrap">
              <div class="featured-icon">
                {{ featuredApp.emoji }}
              </div>
            </div>

            <!-- 文字信息 -->
            <div class="featured-info">
              <h3 class="featured-title">
                {{ featuredApp.name }}
              </h3>
              <p class="featured-tagline">
                {{ featuredApp.tagline || featuredApp.description }}
              </p>
            </div>
          </div>

          <!-- 底部：CTA 按钮 -->
          <div class="featured-footer">
            <button class="featured-cta" type="button">
              查看
              <svg class="featured-cta-arrow" viewBox="0 0 16 16" fill="none">
                <path d="M3 8h10M9 4l4 4-4 4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* ── 卡片外壳 ── */
.featured-card {
  border-radius: 20px;
  overflow: hidden;
  transition: transform 0.18s cubic-bezier(0.34, 1.56, 0.64, 1);
  will-change: transform;
}

.featured-card:active {
  transform: scale(0.975);
  transition: transform 0.08s ease-out;
}

/* ── 卡片内部容器 ── */
.featured-body {
  border-radius: 20px;
  height: 200px;
  padding: 20px;
  display: flex;
  flex-direction: column;
  box-shadow:
    0 2px 8px rgba(0, 0, 0, 0.12),
    0 8px 24px rgba(0, 0, 0, 0.08),
    inset 0 1px 0 rgba(255, 255, 255, 0.25);
}

/* ── 背景渐变 ── */
.featured-bg {
  position: absolute;
  inset: 0;
  background: linear-gradient(
    145deg,
    color-mix(in srgb, var(--app-color) 95%, white 5%) 0%,
    color-mix(in srgb, var(--app-color) 70%, black 30%) 100%
  );
  z-index: 0;
}

/* ── 装饰光晕 ── */
.featured-orb {
  position: absolute;
  border-radius: 50%;
  pointer-events: none;
  z-index: 1;
}

.featured-orb-1 {
  width: 180px;
  height: 180px;
  top: -60px;
  right: -40px;
  background: radial-gradient(circle, rgba(255, 255, 255, 0.18) 0%, transparent 70%);
}

.featured-orb-2 {
  width: 120px;
  height: 120px;
  bottom: -30px;
  left: 10px;
  background: radial-gradient(circle, rgba(255, 255, 255, 0.1) 0%, transparent 70%);
}

/* ── 内容层（置于装饰层之上） ── */
.featured-content {
  position: relative;
  z-index: 2;
  height: 100%;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}

/* ── 顶部徽章 ── */
.featured-badge {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: rgba(255, 255, 255, 0.85);
  background: rgba(255, 255, 255, 0.15);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  border: 1px solid rgba(255, 255, 255, 0.2);
  border-radius: 100px;
  padding: 3px 10px 3px 6px;
  width: fit-content;
}

.featured-badge-dot {
  display: block;
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.9);
  box-shadow: 0 0 0 2px rgba(255, 255, 255, 0.25);
}

/* ── 中部：图标 + 文字横排 ── */
.featured-main {
  display: flex;
  align-items: center;
  gap: 14px;
  flex: 1;
  padding: 10px 0 4px;
}

/* ── 图标 ── */
.featured-icon-wrap {
  flex-shrink: 0;
  padding: 3px;
  border-radius: 22px;
  background: rgba(255, 255, 255, 0.18);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  border: 1px solid rgba(255, 255, 255, 0.28);
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
}

.featured-icon {
  width: 64px;
  height: 64px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 18px;
  background: rgba(255, 255, 255, 0.92);
  font-size: 36px;
  line-height: 1;
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.8);
}

/* ── 文字信息 ── */
.featured-info {
  flex: 1;
  min-width: 0;
}

.featured-title {
  font-size: 22px;
  font-weight: 700;
  color: #fff;
  letter-spacing: -0.3px;
  line-height: 1.2;
  margin: 0 0 5px;
  text-shadow: 0 1px 3px rgba(0, 0, 0, 0.15);
}

.featured-tagline {
  font-size: 13px;
  font-weight: 400;
  color: rgba(255, 255, 255, 0.82);
  line-height: 1.45;
  margin: 0;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

/* ── 底部 CTA ── */
.featured-footer {
  display: flex;
  justify-content: flex-end;
}

.featured-cta {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  height: 30px;
  padding: 0 14px 0 16px;
  border-radius: 100px;
  background: rgba(255, 255, 255, 0.95);
  color: color-mix(in srgb, var(--app-color) 90%, black 10%);
  font-size: 13px;
  font-weight: 600;
  border: none;
  cursor: pointer;
  box-shadow:
    0 1px 4px rgba(0, 0, 0, 0.15),
    inset 0 1px 0 rgba(255, 255, 255, 0.9);
  transition:
    opacity 0.15s ease,
    transform 0.15s ease;
  letter-spacing: -0.1px;
}

.featured-cta:active {
  opacity: 0.8;
  transform: scale(0.96);
}

.featured-cta-arrow {
  width: 14px;
  height: 14px;
  flex-shrink: 0;
}
</style>
