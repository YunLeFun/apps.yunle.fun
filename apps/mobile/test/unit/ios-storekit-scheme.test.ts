import { existsSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'

import { describe, expect, it } from 'vitest'

const ROOT = resolve(import.meta.dirname, '../..')
const SCHEMES_DIR = resolve(
  ROOT,
  'ios/App/App.xcodeproj/xcshareddata/xcschemes',
)

describe('iOS StoreKit 测试环境', () => {
  it('默认 App 使用 App Store Sandbox，本地人民币配置仅由预览 Scheme 启用', () => {
    const appScheme = readFileSync(resolve(SCHEMES_DIR, 'App.xcscheme'), 'utf8')
    const localSchemePath = resolve(SCHEMES_DIR, 'App-LocalStoreKit.xcscheme')

    expect(appScheme).not.toContain('StoreKitConfigurationFileReference')
    expect(existsSync(localSchemePath)).toBe(true)

    const localScheme = readFileSync(localSchemePath, 'utf8')
    expect(localScheme).toContain('StoreKitConfigurationFileReference')
    expect(localScheme).toContain('identifier = "../Products.storekit"')
  })
})
