import { mockNuxtImport } from '@nuxt/test-utils/runtime'
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { useScanner } from '../../app/composables/useScanner'

const decodeQr = vi.hoisted(() => vi.fn())
const showError = vi.fn()
const showWarning = vi.fn()

vi.mock('jsqr', () => ({
  default: decodeQr,
}))

mockNuxtImport('useToast', () => () => ({
  showError,
  showWarning,
}))

beforeAll(async () => {
  await useRouter().isReady()
})

describe('scanner album picker', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.spyOn(URL, 'createObjectURL').mockReturnValue('blob:workshop-qr')
    vi.spyOn(URL, 'revokeObjectURL').mockImplementation(() => {})
    decodeQr.mockReturnValue({ data: 'https://apps.yunle.fun/w/7KM2QX' })

    vi.stubGlobal('Image', class {
      width = 1
      height = 1
      onload: null | (() => void) = null
      onerror: null | (() => void) = null
      private imageSource = ''

      get src() {
        return this.imageSource
      }

      set src(value: string) {
        this.imageSource = value
        queueMicrotask(() => this.onload?.())
      }
    })

    vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue({
      drawImage: vi.fn(),
      getImageData: vi.fn(() => ({
        data: new Uint8ClampedArray(4),
        width: 1,
        height: 1,
      })),
    } as unknown as CanvasRenderingContext2D)
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('opens the browser file picker and decodes the selected QR image', async () => {
    const { scanFromAlbum } = useScanner()

    vi.spyOn(HTMLInputElement.prototype, 'click').mockImplementation(function (this: HTMLInputElement) {
      Object.defineProperty(this, 'files', { value: [new File(['qr'], 'qr.png', { type: 'image/png' })] })
      this.dispatchEvent(new Event('change'))
    })
    await expect(scanFromAlbum()).resolves.toBe('https://apps.yunle.fun/w/7KM2QX')
    expect(showError).not.toHaveBeenCalled()
  })
})
