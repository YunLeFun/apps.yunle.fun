import { Capacitor } from '@capacitor/core'
import { mockNuxtImport } from '@nuxt/test-utils/runtime'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { useScanner } from '../../app/composables/useScanner'

const cameraMocks = vi.hoisted(() => ({
  chooseFromGallery: vi.fn(),
}))
const decodeQr = vi.hoisted(() => vi.fn())
const showError = vi.fn()
const showWarning = vi.fn()

vi.mock('@capacitor/camera', () => ({
  Camera: {
    chooseFromGallery: cameraMocks.chooseFromGallery,
  },
  MediaTypeSelection: {
    Photo: 'photo',
  },
}))

vi.mock('jsqr', () => ({
  default: decodeQr,
}))

mockNuxtImport('useToast', () => () => ({
  showError,
  showWarning,
}))

describe('scanner album picker', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.spyOn(Capacitor, 'isNativePlatform').mockReturnValue(true)
    cameraMocks.chooseFromGallery.mockResolvedValue({
      results: [{
        webPath: 'capacitor://localhost/_capacitor_file_/tmp/workshop-qr.png',
      }],
    })
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

  it('opens the native photo gallery and decodes the selected QR image', async () => {
    const { scanFromAlbum } = useScanner()

    await expect(scanFromAlbum()).resolves.toBe('https://apps.yunle.fun/w/7KM2QX')
    expect(cameraMocks.chooseFromGallery).toHaveBeenCalledOnce()
    expect(showError).not.toHaveBeenCalled()
  })
})
