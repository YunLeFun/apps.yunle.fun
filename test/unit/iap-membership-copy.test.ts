import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

import { describe, expect, it } from 'vitest'
import { PRODUCTS } from '../../scripts/create-iap-products.mjs'

const ROOT = resolve(import.meta.dirname, '../..')
const storeKit = JSON.parse(
  readFileSync(resolve(ROOT, 'ios/App/Products.storekit'), 'utf8'),
)

describe('app store 非续订会员商品文案', () => {
  it.each([
    ['fun.yunle.apps.member_month', '自然月', 'calendar month'],
    ['fun.yunle.apps.member_year', '自然年', 'calendar year'],
  ])('%s 的 ASC 创建文案使用对应自然周期', (productId, zhPeriod, enPeriod) => {
    const product = PRODUCTS.find(item => item.productId === productId)
    expect(product?.zh.description).toContain(zhPeriod)
    expect(product?.en.description).toContain(enPeriod)
    expect(`${product?.zh.description} ${product?.en.description}`).not.toMatch(/31 天|366 天|31 days|366 days/)
  })

  it.each([
    ['fun.yunle.apps.member_month', '自然月', '自然年'],
    ['fun.yunle.apps.member_year', '自然年', '自然月'],
  ])('%s 的本地 StoreKit 配置使用正确周期', (productId, expectedPeriod, wrongPeriod) => {
    const product = storeKit.nonRenewingSubscriptions
      .find(item => item.productID === productId)
    const descriptions = product?.localizations
      .map(localization => localization.description)
      .join(' ') ?? ''

    expect(descriptions).toContain(expectedPeriod)
    expect(descriptions).not.toContain(wrongPeriod)
    expect(descriptions).not.toMatch(/31 天|366 天|31 days|366 days/)
  })
})
