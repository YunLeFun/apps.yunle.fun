import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

import { describe, expect, it } from 'vitest'

const ROOT = resolve(import.meta.dirname, '../..')
const membershipPage = readFileSync(resolve(ROOT, 'app/pages/membership.vue'), 'utf8')
const walletPage = readFileSync(resolve(ROOT, 'app/pages/wallet.vue'), 'utf8')
const colorTokens = readFileSync(resolve(ROOT, 'app/styles/css/css-vars.css'), 'utf8')

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
})
