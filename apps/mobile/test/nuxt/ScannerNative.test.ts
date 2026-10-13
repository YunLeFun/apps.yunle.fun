import { flushPromises, mount } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import ScannerBarcode from '../../app/components/scanner/Barcode.vue'

const scannerMocks = vi.hoisted(() => ({
  scanBarcode: vi.fn(),
}))

vi.mock('@capacitor/core', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@capacitor/core')>()
  return {
    ...actual,
    Capacitor: {
      ...actual.Capacitor,
      isNativePlatform: () => true,
    },
  }
})

vi.mock('@capacitor/barcode-scanner', () => ({
  CapacitorBarcodeScanner: {
    scanBarcode: scannerMocks.scanBarcode,
  },
  CapacitorBarcodeScannerCameraDirection: {
    BACK: 1,
  },
  CapacitorBarcodeScannerTypeHintALLOption: {
    ALL: 17,
  },
}))

describe('native barcode scanner', () => {
  const getUserMedia = vi.fn()

  beforeEach(() => {
    vi.clearAllMocks()
    scannerMocks.scanBarcode.mockResolvedValue({
      ScanResult: 'https://apps.yunle.fun/w/7KM2QX',
      format: 0,
    })
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: { getUserMedia },
    })
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('uses the native plugin instead of getUserMedia inside Capacitor', async () => {
    const wrapper = mount(ScannerBarcode, {
      props: {
        isVisible: true,
      },
      global: {
        stubs: {
          IonButton: true,
          IonIcon: true,
          IonSpinner: true,
        },
      },
    })

    await flushPromises()

    expect(scannerMocks.scanBarcode).toHaveBeenCalledWith({
      hint: 17,
      cameraDirection: 1,
      scanInstructions: '将二维码或条形码放入框内',
      cancelButtonAccessibilityLabel: '取消扫码',
      torchButtonOnAccessibilityLabel: '关闭手电筒',
      torchButtonOffAccessibilityLabel: '打开手电筒',
    })
    expect(getUserMedia).not.toHaveBeenCalled()
    expect(wrapper.emitted('result')).toEqual([
      ['https://apps.yunle.fun/w/7KM2QX'],
    ])
  })
})
