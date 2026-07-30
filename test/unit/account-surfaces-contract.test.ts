import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

import { describe, expect, it } from 'vitest'

const ROOT = resolve(import.meta.dirname, '../..')
const membershipPage = readFileSync(resolve(ROOT, 'app/pages/membership.vue'), 'utf8')
const walletPage = readFileSync(resolve(ROOT, 'app/pages/wallet.vue'), 'utf8')
const mePage = readFileSync(resolve(ROOT, 'app/pages/tabs/me.vue'), 'utf8')
const colorTokens = readFileSync(resolve(ROOT, 'app/styles/css/css-vars.css'), 'utf8')
const listOverrides = readFileSync(resolve(ROOT, 'app/styles/scss/override.scss'), 'utf8')

function getMeListItem(title: string) {
  const titleIndex = mePage.indexOf(`title="${title}"`)
  const itemStart = mePage.lastIndexOf('<k-list-item', titleIndex)
  const itemEnd = mePage.indexOf('</k-list-item>', titleIndex)

  expect(titleIndex).toBeGreaterThan(-1)
  expect(itemStart).toBeGreaterThan(-1)
  expect(itemEnd).toBeGreaterThan(titleIndex)

  return mePage.slice(itemStart, itemEnd)
}

describe('钱包与会员页面契约', () => {
  it('会员页每次重新进入时刷新账户快照', () => {
    expect(membershipPage).toContain('onIonViewWillEnter')
    expect(membershipPage).toMatch(
      /onIonViewWillEnter\(\(\) => \{[\s\S]{0,160}userStore\.isLoggedIn[\s\S]{0,80}refresh\(\)/,
    )
  })

  it.each([
    ['会员套餐', membershipPage],
    ['云币充值包', walletPage],
  ])('%s 使用可随亮暗模式变化的表面与边线', (_name, source) => {
    expect(source).not.toContain('--ion-color-step-200')
    expect(source).toContain('color-mix(in srgb, currentColor 12%, transparent)')
    expect(source).toContain('var(--ion-item-background, var(--ion-background-color))')
    expect(source).toContain('color: inherit')
  })

  it('推荐徽标使用高对比度深色文字', () => {
    expect(membershipPage).toMatch(
      /\.plan-badge\s*\{[\s\S]{0,320}font-weight:\s*700;[\s\S]{0,160}color:\s*var\(--ylf-color-warning-on\);/,
    )
  })

  it('会员价格辅助文案使用亮暗模式独立的可访问语义色', () => {
    expect(colorTokens).toContain('--ylf-color-warning-text: #7a4b00')
    expect(colorTokens).toContain('--ylf-color-warning-text: #ffce31')
    expect(membershipPage).toContain('color: var(--ylf-color-warning-text)')
  })

  it('套餐与购买操作具备可访问状态和触控尺寸', () => {
    expect(membershipPage).toContain(':aria-pressed="selectedCycle === opt.cycle"')
    expect(membershipPage).toMatch(/\.purchase-btn\s*\{[\s\S]{0,160}min-height:\s*44px;/)
    expect(membershipPage).toContain('@media (prefers-reduced-motion: reduce)')
    expect(membershipPage).toContain('.plan-card:focus-visible')
  })

  it('恢复购买说明账号范围、扣款行为与执行状态', () => {
    expect(membershipPage).toContain('恢复 App Store 购买')
    expect(membershipPage).toContain('当前 Apple 账户')
    expect(membershipPage).toContain('不会重复扣款')
    expect(membershipPage).toContain(':disabled="restoring"')
    expect(membershipPage).toContain(':aria-busy="restoring"')
  })

  it('钱包使用 Konsta 标准导航箭头并限制余额宽度', () => {
    const walletItem = getMeListItem('钱包')

    expect(walletItem).not.toContain(':chevron="false"')
    expect(walletItem).not.toContain('class="wallet-after"')
    expect(walletItem).not.toContain('class="wallet-chevron"')
    expect(walletItem).toContain('class="wallet-balance"')
    expect(mePage).not.toContain('chevronForward')
    expect(mePage).toMatch(
      /\.wallet-balance\s*\{[\s\S]{0,180}max-width:\s*min\(46vw,\s*200px\);[\s\S]{0,180}text-overflow:\s*ellipsis;/,
    )
  })

  it.each([
    '我的个人工坊',
    '已加入的工坊',
    '钱包',
    '会员',
    '我的应用',
    '我的举报',
  ])('“我”页的“%s”使用统一的 Apple 两行导航样式', (title) => {
    const item = getMeListItem(title)

    expect(item).toMatch(/\b:?subtitle=/)
    expect(item).not.toMatch(/\b:?footer=/)
    expect(item).toContain(':strong-title="false"')
    expect(item).toContain('inner-class="k-list-item-vcenter"')
  })

  it('两行导航项将状态与 disclosure indicator 分列并相对整行居中', () => {
    expect(listOverrides).toMatch(
      /\.k-list-item-vcenter\s*\{[\s\S]{0,160}grid-template-columns:\s*minmax\(0,\s*1fr\)\s+auto\s+auto;/,
    )
    expect(listOverrides).toMatch(
      /> \.flex\.justify-between[\s\S]{0,600}> div\.shrink-0\s*\{[\s\S]{0,100}grid-column:\s*2;[\s\S]{0,100}grid-row:\s*1\s*\/\s*span\s*2;/,
    )
    expect(listOverrides).toMatch(
      /> svg\s*\{[\s\S]{0,100}grid-column:\s*3;[\s\S]{0,100}grid-row:\s*1\s*\/\s*span\s*2;/,
    )
    expect(listOverrides).toMatch(
      /> \.flex\.justify-between ~ div\s*\{[\s\S]{0,160}color:\s*var\(--ylf-label-secondary\);/,
    )
  })
})
