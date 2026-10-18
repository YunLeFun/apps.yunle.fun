<script setup lang="ts">
/**
 * apps.yunle.fun 根路径：原生客户端展示与下载页
 *
 * 发布会式叙事：首屏机身随滚动“立起”，随后机身固定在舞台上，
 * 章节滚过时截图交叉溶解，背景光随章节变色。全部动效基于原生
 * IntersectionObserver / rAF / CSS，系统开启“减弱动态效果”时退化为淡入。
 *
 * 网页版仍在 /tabs/*；原生壳与主屏幕网页由 web-entry 中间件直接分流进应用。
 */
import { IonPage } from '@ionic/vue'
import {
  SHOWCASE_CRAFT,
  SHOWCASE_DOWNLOADS,
  SHOWCASE_FEATURES,
  WEB_APP_ENTRY,
  WEB_ENTRY_STORAGE_KEY,
} from '~/constants/showcase'

definePageMeta({
  middleware: 'web-entry',
})

useHead({
  title: '云乐坊 · 一个 App，装下所有云应用',
  meta: [
    { name: 'description', content: '云乐坊原生客户端：在工坊发现云应用，把喜欢的带回云居，轻点即用，无需安装。' },
    { property: 'og:title', content: '云乐坊 · 一个 App，装下所有云应用' },
    { property: 'og:url', content: 'https://apps.yunle.fun' },
  ],
})

const router = useRouter()
const { catalog, ensureLoaded } = useAppCatalog()

const scroller = ref<HTMLElement>()
const hero = ref<HTMLElement>()
const activeFeature = ref(0)
const scrolled = ref(false)
const platform = ref<'ios' | 'android' | 'desktop'>('desktop')

const shots = SHOWCASE_FEATURES.map(feature => ({ src: feature.shot, alt: feature.alt }))
const glow = computed(() => SHOWCASE_FEATURES[activeFeature.value]?.glow ?? '#0a84ff')

const iconApps = computed(() => catalog.value.filter(app => app.logo || app.iconAssets || app.emoji).slice(0, 24))
const iconRows = computed(() => {
  const apps = iconApps.value
  const half = Math.ceil(apps.length / 2)
  return [apps.slice(0, half), apps.slice(half)].filter(row => row.length)
})
const appCount = computed(() => Math.max(catalog.value.length, 1))

function openWebApp() {
  try {
    localStorage.setItem(WEB_ENTRY_STORAGE_KEY, 'app')
  }
  catch {}
  router.push(WEB_APP_ENTRY)
}

function scrollToId(id: string) {
  const target = scroller.value?.querySelector<HTMLElement>(`#${id}`)
  target?.scrollIntoView({ behavior: prefersReducedMotion() ? 'auto' : 'smooth', block: 'start' })
}

function scrollToFeature(index: number) {
  const step = scroller.value?.querySelectorAll<HTMLElement>('.step')[index]
  step?.scrollIntoView({ behavior: prefersReducedMotion() ? 'auto' : 'smooth', block: 'center' })
}

function prefersReducedMotion() {
  return import.meta.client && window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

const observers: IntersectionObserver[] = []
let frame = 0

/** 首屏随滚动的进度（0 → 1），写入 CSS 变量，由样式决定具体形变。 */
function updateHero() {
  frame = 0
  const root = scroller.value
  const el = hero.value
  if (!root || !el)
    return
  scrolled.value = root.scrollTop > 8
  const progress = Math.min(1, Math.max(0, root.scrollTop / (el.offsetHeight * 0.7)))
  el.style.setProperty('--p', progress.toFixed(4))
}

function onScroll() {
  if (!frame)
    frame = requestAnimationFrame(updateHero)
}

function countUp(el: HTMLElement) {
  const target = Number(el.dataset.count || 0)
  const suffix = el.dataset.suffix || ''
  if (prefersReducedMotion() || target === 0) {
    el.textContent = `${target}${suffix}`
    return
  }
  const start = performance.now()
  const duration = 1400
  const tick = (now: number) => {
    const t = Math.min(1, (now - start) / duration)
    const eased = 1 - 2 ** (-10 * t)
    el.textContent = `${Math.round(target * (t === 1 ? 1 : eased))}${suffix}`
    if (t < 1)
      requestAnimationFrame(tick)
  }
  requestAnimationFrame(tick)
}

onMounted(() => {
  const ua = navigator.userAgent
  platform.value = /iPhone|iPad|iPod/.test(ua) || (ua.includes('Mac') && navigator.maxTouchPoints > 1)
    ? 'ios'
    : /Android/i.test(ua) ? 'android' : 'desktop'

  ensureLoaded()
  const root = scroller.value!
  root.addEventListener('scroll', onScroll, { passive: true })
  updateHero()

  // 章节激活线：桌面取视口中线，窄屏机身固定在上半部，取下方文字区。
  const narrow = window.matchMedia('(max-width: 860px)').matches
  const steps = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting)
        activeFeature.value = Number((entry.target as HTMLElement).dataset.index)
    }
  }, { root, rootMargin: narrow ? '-58% 0px -30% 0px' : '-48% 0px -48% 0px' })
  root.querySelectorAll('.step').forEach(el => steps.observe(el))
  observers.push(steps)

  const reveal = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting)
        continue
      const el = entry.target as HTMLElement
      el.classList.add('is-in')
      el.querySelectorAll<HTMLElement>('[data-count]').forEach(countUp)
      reveal.unobserve(el)
    }
  }, { root, threshold: 0.18 })
  root.querySelectorAll('[data-reveal]').forEach(el => reveal.observe(el))
  observers.push(reveal)
})

onBeforeUnmount(() => {
  scroller.value?.removeEventListener('scroll', onScroll)
  observers.forEach(observer => observer.disconnect())
  if (frame)
    cancelAnimationFrame(frame)
})
</script>

<template>
  <IonPage>
    <div ref="scroller" class="showcase" :style="{ '--glow': glow }">
      <header class="nav" :class="{ 'is-scrolled': scrolled }">
        <a class="nav-brand" href="/?showcase" @click.prevent="scroller?.scrollTo({ top: 0, behavior: 'smooth' })">
          <img src="/ylf.svg" alt="" width="28" height="28">
          <span>云乐坊</span>
        </a>
        <nav class="nav-links" aria-label="页面导航">
          <button type="button" @click="scrollToId('features')">
            功能
          </button>
          <button type="button" @click="scrollToId('craft')">
            设计
          </button>
          <button type="button" @click="scrollToId('download')">
            下载
          </button>
        </nav>
        <button type="button" class="nav-cta" @click="openWebApp">
          打开网页版
        </button>
      </header>

      <!-- 首屏 -->
      <section ref="hero" class="hero" aria-labelledby="hero-title">
        <div class="hero-aura" aria-hidden="true" />
        <div class="hero-copy">
          <p class="eyebrow hero-in" style="--d: 0">
            云乐坊 · 原生 iOS 客户端
          </p>
          <h1 id="hero-title" class="hero-title">
            <span class="hero-in" style="--d: 1">一个 App，</span>
            <span class="hero-in gradient-text" style="--d: 2">装下所有云应用。</span>
          </h1>
          <p class="hero-sub hero-in" style="--d: 3">
            在工坊发现，把喜欢的带回云居。轻点即用，无需安装。
          </p>
          <div class="hero-actions hero-in" style="--d: 4">
            <button type="button" class="btn btn-primary" @click="scrollToId('download')">
              获取 App
            </button>
            <button type="button" class="btn btn-ghost" @click="openWebApp">
              在网页中使用
              <Icon name="ri:arrow-right-up-line" size="16px" />
            </button>
          </div>
        </div>
        <div class="hero-device-wrap hero-rise">
          <div class="hero-device">
            <ShowcaseDevice :shots="[shots[0]!]" eager />
          </div>
        </div>
        <button type="button" class="hero-scroll-hint" aria-label="向下浏览功能" @click="scrollToId('apps')">
          <Icon name="ri:arrow-down-line" size="20px" />
        </button>
      </section>

      <!-- 应用墙 -->
      <section id="apps" class="apps" aria-labelledby="apps-title">
        <div class="section-head" data-reveal>
          <p class="eyebrow">
            工坊
          </p>
          <h2 id="apps-title" class="section-title">
            {{ appCount }}+ 款云应用，<br>一个都不用安装。
          </h2>
        </div>
        <div class="marquee" aria-label="部分云应用">
          <div
            v-for="(row, rowIndex) in iconRows"
            :key="rowIndex"
            class="marquee-row"
            :class="{ 'is-reverse': rowIndex % 2 === 1 }"
          >
            <div class="marquee-track">
              <div
                v-for="(app, index) in [...row, ...row]"
                :key="`${app.id}-${index}`"
                class="marquee-item"
                :aria-hidden="index >= row.length"
              >
                <AppIconBox :icon="app.logo" :icon-assets="app.iconAssets" :emoji="app.emoji" :color="app.themeColor" size="md" appearance="dark" />
                <span>{{ app.name }}</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- 功能舞台 -->
      <section id="features" class="theater" aria-label="功能介绍">
        <div class="theater-stage">
          <div class="stage-glow" aria-hidden="true" />
          <div class="stage-device">
            <ShowcaseDevice :shots="shots" :active="activeFeature" />
          </div>
          <div class="stage-tabs" role="tablist" aria-label="功能章节">
            <button
              v-for="(feature, index) in SHOWCASE_FEATURES"
              :key="feature.id"
              type="button"
              role="tab"
              :aria-selected="index === activeFeature"
              :class="{ 'is-active': index === activeFeature }"
              @click="scrollToFeature(index)"
            >
              {{ feature.kicker }}
            </button>
          </div>
        </div>
        <div class="theater-steps">
          <article
            v-for="(feature, index) in SHOWCASE_FEATURES"
            :key="feature.id"
            class="step"
            :class="{ 'is-active': index === activeFeature }"
            :data-index="index"
          >
            <p class="eyebrow" :style="{ color: feature.glow }">
              {{ feature.kicker }}
            </p>
            <h2 class="step-title">
              {{ feature.title }}
            </h2>
            <p class="step-body">
              {{ feature.body }}
            </p>
            <ul class="step-points">
              <li v-for="point in feature.points" :key="point">
                {{ point }}
              </li>
            </ul>
          </article>
        </div>
      </section>

      <!-- 原生细节 -->
      <section id="craft" class="craft" aria-labelledby="craft-title">
        <div class="section-head" data-reveal>
          <p class="eyebrow">
            原生打造
          </p>
          <h2 id="craft-title" class="section-title">
            每个细节，<br>都像 iPhone 本该有的样子。
          </h2>
        </div>
        <div class="craft-grid">
          <article
            v-for="(item, index) in SHOWCASE_CRAFT"
            :key="item.title"
            class="craft-card"
            data-reveal
            :style="{ '--i': index }"
          >
            <Icon :name="item.icon" size="28px" class="craft-icon" />
            <h3>{{ item.title }}</h3>
            <p>{{ item.body }}</p>
          </article>
        </div>
      </section>

      <!-- 数字 -->
      <section class="stats" aria-label="云乐坊数字" data-reveal>
        <div class="stat">
          <strong :data-count="appCount" data-suffix="+">{{ appCount }}+</strong>
          <span>款云应用</span>
        </div>
        <div class="stat">
          <strong data-count="0">0</strong>
          <span>次下载安装</span>
        </div>
        <div class="stat">
          <strong data-count="1">1</strong>
          <span>个账号通行</span>
        </div>
      </section>

      <!-- 下载 -->
      <section id="download" class="download" aria-labelledby="download-title">
        <div class="download-aura" aria-hidden="true" />
        <div class="download-inner" data-reveal>
          <img class="download-icon" src="/showcase/app-icon.png" alt="" width="104" height="104">
          <h2 id="download-title" class="section-title">
            现在，就开始。
          </h2>
          <p class="download-sub">
            原生客户端即将登陆 App Store。等待期间，网页版随时可用。
          </p>
          <div class="download-actions">
            <component
              :is="SHOWCASE_DOWNLOADS.appStore ? 'a' : 'span'"
              class="store-btn"
              :class="{ 'is-primary': platform === 'ios', 'is-pending': !SHOWCASE_DOWNLOADS.appStore }"
              :href="SHOWCASE_DOWNLOADS.appStore || undefined"
              :aria-disabled="!SHOWCASE_DOWNLOADS.appStore || undefined"
            >
              <Icon name="ri:apple-fill" size="26px" />
              <span>
                <small>{{ SHOWCASE_DOWNLOADS.appStore ? '前往' : '即将上架' }}</small>
                App Store
              </span>
            </component>
            <component
              :is="SHOWCASE_DOWNLOADS.android ? 'a' : 'span'"
              class="store-btn"
              :class="{ 'is-primary': platform === 'android', 'is-pending': !SHOWCASE_DOWNLOADS.android }"
              :href="SHOWCASE_DOWNLOADS.android || undefined"
              :aria-disabled="!SHOWCASE_DOWNLOADS.android || undefined"
            >
              <Icon name="ri:android-fill" size="26px" />
              <span>
                <small>{{ SHOWCASE_DOWNLOADS.android ? '下载' : '即将上架' }}</small>
                Android
              </span>
            </component>
            <button type="button" class="store-btn is-web" @click="openWebApp">
              <Icon name="ri:global-line" size="26px" />
              <span>
                <small>立即使用</small>
                网页版
              </span>
            </button>
          </div>
        </div>
      </section>

      <footer class="footer">
        <span>© {{ new Date().getFullYear() }} 云乐坊 · 让世界有趣多彩</span>
        <nav aria-label="法律信息">
          <a href="https://www.yunle.fun/docs/privacy-policy" target="_blank" rel="noopener">隐私政策</a>
          <a href="https://www.yunle.fun/docs/terms-of-service" target="_blank" rel="noopener">服务条款</a>
          <a href="https://www.yunle.fun" target="_blank" rel="noopener">官网</a>
        </nav>
      </footer>
    </div>
  </IonPage>
</template>

<style scoped>
.showcase {
  --bg: #000;
  --fg: #f5f5f7;
  --muted: #a1a1a6;
  --hairline: rgb(255 255 255 / 0.1);
  --ease-out: cubic-bezier(0.22, 1, 0.36, 1);
  --gutter: clamp(16px, 5vw, 64px);

  position: absolute;
  inset: 0;
  overflow-x: hidden;
  overflow-y: auto;
  overscroll-behavior-y: none;
  -webkit-overflow-scrolling: touch;
  background: var(--bg);
  color: var(--fg);
  font-family:
    -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'PingFang SC', 'Hiragino Sans GB', 'Helvetica Neue', sans-serif;
  -webkit-font-smoothing: antialiased;
  scroll-behavior: auto;
}

.showcase :is(h1, h2, h3, p) {
  margin: 0;
}

.showcase button {
  font: inherit;
  color: inherit;
  cursor: pointer;
}

.showcase :focus-visible {
  outline: 2px solid #2997ff;
  outline-offset: 3px;
}

.eyebrow {
  font-size: clamp(13px, 1.4vw, 17px);
  font-weight: 600;
  letter-spacing: 0.02em;
  color: var(--muted);
}

.gradient-text {
  background: linear-gradient(100deg, #2997ff 0%, #a970ff 45%, #ff6aa6 100%);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

.section-head {
  max-width: 980px;
  margin: 0 auto;
  padding: 0 var(--gutter);
  text-align: center;
}

.section-title {
  margin-top: 12px !important;
  font-size: clamp(32px, 6vw, 72px);
  font-weight: 700;
  line-height: 1.08;
  letter-spacing: -0.02em;
}

/* 导航：滚动后变为玻璃材质 */
.nav {
  position: sticky;
  top: 0;
  z-index: 20;
  display: flex;
  align-items: center;
  gap: 24px;
  height: 56px;
  padding: 0 var(--gutter);
  padding-top: env(safe-area-inset-top);
  box-sizing: content-box;
  transition:
    background-color 0.3s,
    border-color 0.3s;
  border-bottom: 1px solid transparent;
}

.nav.is-scrolled {
  background: rgb(22 22 23 / 0.72);
  border-bottom-color: var(--hairline);
  backdrop-filter: saturate(180%) blur(20px);
  -webkit-backdrop-filter: saturate(180%) blur(20px);
}

.nav-brand {
  display: flex;
  align-items: center;
  gap: 8px;
  color: var(--fg);
  font-weight: 600;
  font-size: 17px;
  text-decoration: none;
}

.nav-links {
  display: flex;
  gap: 4px;
  margin-left: auto;
}

.nav-links button {
  padding: 8px 12px;
  border: 0;
  border-radius: 999px;
  background: none;
  color: var(--muted);
  font-size: 14px;
  transition: color 0.2s;
}

.nav-links button:hover {
  color: var(--fg);
}

.nav-cta {
  padding: 7px 14px;
  border: 0;
  border-radius: 999px;
  background: #0071e3;
  font-size: 14px;
  font-weight: 500;
  transition: background-color 0.2s;
}

.nav-cta:hover {
  background: #0077ed;
}

/* 首屏 */
.hero {
  --p: 0;
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  min-height: calc(100svh - 56px);
  padding: clamp(32px, 8vh, 88px) var(--gutter) 0;
  overflow: hidden;
  text-align: center;
}

.hero-aura {
  position: absolute;
  inset: -20% -10% auto;
  height: 120%;
  background:
    radial-gradient(40% 35% at 30% 55%, rgb(41 151 255 / 0.32), transparent 70%),
    radial-gradient(35% 30% at 70% 60%, rgb(191 90 242 / 0.28), transparent 70%),
    radial-gradient(30% 25% at 50% 80%, rgb(255 55 95 / 0.18), transparent 70%);
  filter: blur(20px);
  opacity: calc(1 - var(--p));
  animation: aura-drift 18s ease-in-out infinite alternate;
  pointer-events: none;
}

.hero-copy {
  position: relative;
  max-width: 900px;
  opacity: calc(1 - var(--p) * 1.3);
  transform: translateY(calc(var(--p) * -60px)) scale(calc(1 - var(--p) * 0.06));
}

.hero-title {
  margin-top: 16px !important;
  /* 窄屏按 8 个汉字一行计算，避免“用。”单独掉行 */
  font-size: clamp(34px, min(10.5vw, 9vw + 8px), 112px);
  font-weight: 800;
  text-wrap: balance;
  line-height: 1.02;
  letter-spacing: -0.035em;
}

.hero-title span {
  display: block;
}

.hero-sub {
  margin: 24px auto 0 !important;
  max-width: 34em;
  font-size: clamp(17px, 2vw, 24px);
  line-height: 1.45;
  color: var(--muted);
}

.hero-actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 12px;
  margin-top: 32px;
}

.btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-height: 48px;
  padding: 0 24px;
  border-radius: 999px;
  font-size: 17px;
  font-weight: 600;
  transition:
    transform 0.25s var(--ease-out),
    background-color 0.2s;
}

.btn:active {
  transform: scale(0.96);
}

.btn-primary {
  border: 0;
  background: var(--fg);
  color: #000 !important;
}

.btn-primary:hover {
  background: #fff;
}

.btn-ghost {
  border: 1px solid rgb(255 255 255 / 0.28);
  background: rgb(255 255 255 / 0.06);
  backdrop-filter: blur(12px);
}

.btn-ghost:hover {
  background: rgb(255 255 255 / 0.12);
}

.hero-device-wrap {
  position: relative;
  width: min(340px, 70vw);
  margin-top: clamp(40px, 7vh, 72px);
  perspective: 1400px;
}

.hero-device {
  transform-origin: 50% 0%;
  transform: rotateX(calc((1 - var(--p)) * 22deg)) scale(calc(0.9 + var(--p) * 0.1)) translateY(calc(var(--p) * -40px));
  will-change: transform;
}

.hero-scroll-hint {
  position: absolute;
  bottom: 20px;
  left: 50%;
  display: grid;
  place-items: center;
  width: 44px;
  height: 44px;
  border: 1px solid var(--hairline);
  border-radius: 999px;
  background: rgb(255 255 255 / 0.06);
  opacity: calc(1 - var(--p) * 3);
  transform: translateX(-50%);
  animation: hint-bob 2.4s ease-in-out infinite;
}

/* 入场 */
.hero-in {
  opacity: 0;
  filter: blur(12px);
  transform: translateY(24px);
  animation: hero-in 1s var(--ease-out) forwards;
  animation-delay: calc(0.15s + var(--d) * 0.12s);
}

.hero-rise {
  opacity: 0;
  transform: translateY(120px);
  animation: hero-rise 1.4s var(--ease-out) 0.55s forwards;
}

@keyframes hero-in {
  to {
    opacity: 1;
    filter: none;
    transform: none;
  }
}

@keyframes hero-rise {
  to {
    opacity: 1;
    transform: none;
  }
}

@keyframes aura-drift {
  to {
    transform: translate3d(3%, -4%, 0) scale(1.08);
  }
}

@keyframes hint-bob {
  50% {
    translate: 0 6px;
  }
}

/* 应用墙 */
.apps {
  padding: clamp(96px, 16vh, 160px) 0 clamp(64px, 10vh, 120px);
}

.marquee {
  display: grid;
  gap: 20px;
  margin-top: 56px;
  mask-image: linear-gradient(90deg, transparent, #000 12%, #000 88%, transparent);
  -webkit-mask-image: linear-gradient(90deg, transparent, #000 12%, #000 88%, transparent);
}

.marquee-row {
  overflow: hidden;
}

.marquee-track {
  display: flex;
  gap: 28px;
  width: max-content;
  animation: marquee 60s linear infinite;
}

.marquee-row.is-reverse .marquee-track {
  animation-direction: reverse;
  animation-duration: 70s;
}

.marquee:hover .marquee-track {
  animation-play-state: paused;
}

.marquee-item {
  display: grid;
  justify-items: center;
  gap: 10px;
  width: 88px;
  font-size: 13px;
  color: var(--muted);
  text-align: center;
}

.marquee-item span {
  overflow: hidden;
  max-width: 100%;
  white-space: nowrap;
  text-overflow: ellipsis;
}

@keyframes marquee {
  to {
    transform: translateX(-50%);
  }
}

/* 功能舞台 */
.theater {
  position: relative;
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
  gap: 0 clamp(24px, 6vw, 96px);
  padding: 0 var(--gutter);
  max-width: 1200px;
  margin: 0 auto;
}

.theater-stage {
  position: sticky;
  top: 56px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 28px;
  height: calc(100svh - 56px);
}

.stage-glow {
  position: absolute;
  top: 50%;
  left: 50%;
  width: min(520px, 90%);
  aspect-ratio: 1;
  border-radius: 50%;
  background: var(--glow);
  opacity: 0.32;
  filter: blur(90px);
  transform: translate(-50%, -55%);
  transition: background-color 0.8s var(--ease-out);
  pointer-events: none;
}

.stage-device {
  position: relative;
  width: min(330px, calc((100svh - 56px) * 0.72 * 0.46));
}

.stage-tabs {
  position: relative;
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 4px;
  padding: 4px;
  border: 1px solid var(--hairline);
  border-radius: 999px;
  background: rgb(255 255 255 / 0.06);
  backdrop-filter: blur(16px);
  -webkit-backdrop-filter: blur(16px);
}

.stage-tabs button {
  padding: 6px 12px;
  border: 0;
  border-radius: 999px;
  background: transparent;
  color: var(--muted);
  font-size: 13px;
  transition:
    background-color 0.35s var(--ease-out),
    color 0.35s;
}

.stage-tabs button.is-active {
  background: rgb(255 255 255 / 0.92);
  color: #000;
}

.theater-steps {
  display: flex;
  flex-direction: column;
}

.step {
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 18px;
  min-height: calc(100svh - 56px);
  opacity: 0.25;
  transform: translateY(16px);
  transition:
    opacity 0.6s var(--ease-out),
    transform 0.8s var(--ease-out);
}

.step.is-active {
  opacity: 1;
  transform: none;
}

.step-title {
  font-size: clamp(32px, 4.6vw, 60px);
  font-weight: 700;
  line-height: 1.1;
  letter-spacing: -0.025em;
  white-space: pre-line;
}

.step-body {
  max-width: 28em;
  font-size: clamp(17px, 1.7vw, 21px);
  line-height: 1.55;
  color: var(--muted);
}

.step-points {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin: 4px 0 0;
  padding: 0;
  list-style: none;
}

.step-points li {
  padding: 6px 14px;
  border: 1px solid var(--hairline);
  border-radius: 999px;
  background: rgb(255 255 255 / 0.05);
  font-size: 14px;
}

/* 原生细节 */
.craft {
  padding: clamp(96px, 16vh, 180px) var(--gutter) clamp(48px, 8vh, 96px);
}

.craft-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 16px;
  max-width: 1120px;
  margin: 56px auto 0;
}

.craft-card {
  display: grid;
  align-content: start;
  gap: 10px;
  padding: 28px;
  border: 1px solid var(--hairline);
  border-radius: 28px;
  background: linear-gradient(160deg, rgb(255 255 255 / 0.08), rgb(255 255 255 / 0.02));
}

.craft-card h3 {
  margin-top: 8px;
  font-size: 21px;
  font-weight: 650;
}

.craft-card p {
  font-size: 15px;
  line-height: 1.55;
  color: var(--muted);
}

.craft-icon {
  color: #2997ff;
}

/* 数字 */
.stats {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: clamp(32px, 8vw, 120px);
  padding: clamp(64px, 12vh, 140px) var(--gutter);
  text-align: center;
}

.stat strong {
  display: block;
  font-size: clamp(56px, 9vw, 112px);
  font-weight: 800;
  letter-spacing: -0.04em;
  font-variant-numeric: tabular-nums;
  background: linear-gradient(180deg, #fff 20%, #6e6e73);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

.stat span {
  font-size: 17px;
  color: var(--muted);
}

/* 下载 */
.download {
  position: relative;
  padding: clamp(96px, 18vh, 200px) var(--gutter);
  overflow: hidden;
  text-align: center;
}

.download-aura {
  position: absolute;
  left: 50%;
  bottom: -40%;
  width: min(900px, 140vw);
  aspect-ratio: 1;
  border-radius: 50%;
  background: radial-gradient(closest-side, rgb(41 151 255 / 0.35), rgb(169 112 255 / 0.18) 55%, transparent);
  transform: translateX(-50%);
  pointer-events: none;
}

.download-inner {
  position: relative;
  max-width: 760px;
  margin: 0 auto;
}

.download-icon {
  display: block;
  width: 104px;
  height: 104px;
  margin: 0 auto 8px;
  border-radius: 23%;
  box-shadow:
    0 0 0 1px rgb(255 255 255 / 0.22),
    0 20px 60px rgb(41 151 255 / 0.4);
}

.download-sub {
  margin-top: 16px !important;
  font-size: clamp(17px, 2vw, 21px);
  color: var(--muted);
}

.download-actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 12px;
  margin-top: 40px;
}

.store-btn {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  min-width: 176px;
  min-height: 60px;
  padding: 0 20px;
  border: 1px solid rgb(255 255 255 / 0.22);
  border-radius: 16px;
  background: rgb(255 255 255 / 0.06);
  color: var(--fg);
  font-size: 19px;
  font-weight: 600;
  text-align: left;
  text-decoration: none;
  transition:
    transform 0.25s var(--ease-out),
    background-color 0.2s;
}

.store-btn > span {
  display: grid;
  line-height: 1.15;
}

.store-btn small {
  font-size: 11px;
  font-weight: 500;
  color: var(--muted);
}

.store-btn.is-primary:not(.is-pending),
.store-btn.is-web {
  background: var(--fg);
  border-color: transparent;
  color: #000;
}

.store-btn.is-web small {
  color: #6e6e73;
}

.store-btn.is-pending {
  opacity: 0.55;
  cursor: default;
}

.store-btn:not(.is-pending):active {
  transform: scale(0.96);
}

.footer {
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  gap: 12px;
  padding: 24px var(--gutter) calc(24px + env(safe-area-inset-bottom));
  border-top: 1px solid var(--hairline);
  font-size: 12px;
  color: #6e6e73;
}

.footer nav {
  display: flex;
  gap: 20px;
}

.footer a {
  color: inherit;
  text-decoration: none;
}

.footer a:hover {
  color: var(--fg);
}

/* 通用滚动揭示 */
[data-reveal] {
  opacity: 0;
  transform: translateY(32px);
  transition:
    opacity 0.9s var(--ease-out),
    transform 1s var(--ease-out);
  transition-delay: calc(var(--i, 0) * 80ms);
}

[data-reveal].is-in {
  opacity: 1;
  transform: none;
}

/* 窄屏：机身固定在上半部，文字在下方滚过 */
@media (max-width: 860px) {
  .nav-links {
    display: none;
  }

  .nav-cta {
    margin-left: auto;
  }

  .theater {
    grid-template-columns: minmax(0, 1fr);
  }

  .theater-stage {
    z-index: 1;
    justify-content: flex-start;
    gap: 14px;
    height: auto;
    padding: 16px 0 12px;
    background: linear-gradient(#000 85%, transparent);
  }

  .stage-device {
    width: min(200px, 44vw, calc(100svh * 0.22));
  }

  .stage-tabs button {
    padding: 5px 10px;
    font-size: 12px;
  }

  /* 文字块不占满一屏，章节之间留出滚动距离，激活线落在机身下方的可见区 */
  .step {
    justify-content: flex-start;
    align-items: center;
    min-height: 0;
    margin-bottom: 38svh;
    padding-top: 20px;
    text-align: center;
  }

  .step:last-child {
    margin-bottom: 24svh;
  }

  .step-points {
    justify-content: center;
  }

  .craft-grid {
    grid-template-columns: minmax(0, 1fr);
  }
}

@media (min-width: 861px) and (max-width: 1080px) {
  .craft-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

/* 减弱动态效果：只保留淡入，不位移、不缩放、不循环 */
@media (prefers-reduced-motion: reduce) {
  .hero-in,
  .hero-rise {
    filter: none;
    transform: none;
    animation: fade-in 0.4s linear forwards;
    animation-delay: 0s;
  }

  .hero-copy,
  .hero-device {
    transform: none;
  }

  .hero-aura,
  .hero-scroll-hint,
  .marquee-track {
    animation: none;
  }

  .marquee-track {
    flex-wrap: wrap;
    justify-content: center;
    width: auto;
  }

  .marquee-item[aria-hidden='true'] {
    display: none;
  }

  .step,
  [data-reveal] {
    transform: none;
    transition: opacity 0.3s linear;
  }
}

@keyframes fade-in {
  to {
    opacity: 1;
  }
}
</style>
