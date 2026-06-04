// 生成社交分享封面 public/og-image.png (1200×630)
// 用法：node scripts/gen-og-image.mjs
import { chromium } from 'playwright'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

const __dirname = dirname(fileURLToPath(import.meta.url))
const out = resolve(__dirname, '../public/og-image.png')

// 品牌 logo（白色，来自 public/ylf-square.svg 去掉底色方块）
const logo = `<svg viewBox="0 0 128 128" fill="#fff" xmlns="http://www.w3.org/2000/svg">
  <path d="M58.8571 64L44.7143 72.295V55.705L58.8571 64Z"/>
  <path d="M84.5714 64C84.5714 68.3281 81.1176 71.8367 76.8571 71.8367C72.5967 71.8367 69.1429 68.3281 69.1429 64C69.1429 59.6719 72.5967 56.1633 76.8571 56.1633C81.1176 56.1633 84.5714 59.6719 84.5714 64Z"/>
  <path fill-rule="evenodd" clip-rule="evenodd" d="M94 33.5238H34V46.585H21.1429V81.415H34V94.4762H94V81.415H106.857V46.585H94V33.5238ZM94 46.585H34V81.415H94V46.585Z"/>
</svg>`

const apps = [
  ['#007AFF', '🏠'], ['#34C759', '🔍'], ['#FF9500', '🏗️'],
  ['#5856D6', '☁️'], ['#FF3B30', '📱'], ['#AF52DE', '🎮'],
  ['#00C7BE', '📚'], ['#FF2D55', '🎨'], ['#FFD60A', '⚡'],
]

const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><style>
*{margin:0;padding:0;box-sizing:border-box}
body{width:1200px;height:630px;overflow:hidden;position:relative;display:flex;align-items:center;
  font-family:-apple-system,"PingFang SC","Microsoft YaHei",sans-serif;
  background:radial-gradient(125% 110% at 18% -10%,#1a2b4d 0%,#0c1426 50%,#070b15 100%)}
body::before{content:'';position:absolute;top:-220px;left:-120px;width:760px;height:760px;
  background:radial-gradient(circle,rgba(0,122,255,.32),transparent 62%);filter:blur(10px)}
.left{width:640px;padding:0 0 0 92px;position:relative;z-index:2}
.logo{width:112px;height:112px;border-radius:27px;background:linear-gradient(160deg,#0a84ff,#007AFF);
  display:flex;align-items:center;justify-content:center;margin-bottom:40px;
  box-shadow:0 16px 46px rgba(0,122,255,.5),inset 0 1px 0 rgba(255,255,255,.3)}
.logo svg{width:72px;height:72px}
.title{font-size:78px;font-weight:800;color:#fff;letter-spacing:3px;line-height:1}
.subtitle{font-size:32px;color:rgba(255,255,255,.68);margin-top:24px;font-weight:500;letter-spacing:1px}
.domain{font-size:25px;color:#5fa8ff;margin-top:42px;font-weight:600;letter-spacing:2px}
.grid{position:absolute;right:-48px;top:50%;transform:translateY(-50%) rotate(-12deg);
  display:grid;grid-template-columns:repeat(3,130px);gap:28px;z-index:1}
.app{width:130px;height:130px;border-radius:30px;display:flex;align-items:center;justify-content:center;
  font-size:62px;box-shadow:0 18px 44px rgba(0,0,0,.45),inset 0 1px 0 rgba(255,255,255,.28)}
</style></head><body>
  <div class="left">
    <div class="logo">${logo}</div>
    <div class="title">云乐坊</div>
    <div class="subtitle">云应用聚合平台 · 点击即用</div>
    <div class="domain">yunle.fun</div>
  </div>
  <div class="grid">
    ${apps.map(([c, e]) => `<div class="app" style="background:${c}">${e}</div>`).join('')}
  </div>
</body></html>`

const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 2 })
await page.setContent(html, { waitUntil: 'networkidle' })
await page.screenshot({ path: out })
await browser.close()
console.log('✅ 生成', out)
