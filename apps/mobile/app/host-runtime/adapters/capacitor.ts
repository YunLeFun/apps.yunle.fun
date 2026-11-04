import type { HostApplication, HostBrowser, HostEnvironment, HostHaptics, NativeBarcodeResult } from '../capabilities'
import type { HostRuntimePlugin } from '../contracts'
import { App } from '@capacitor/app'
import { Browser } from '@capacitor/browser'
import { Capacitor, registerPlugin } from '@capacitor/core'
import { Haptics, ImpactStyle, NotificationType } from '@capacitor/haptics'

/** Current transport facts; evaluated at call time for launch and test isolation. */
export const hostEnvironment: HostEnvironment = {
  isNative: () => Capacitor.isNativePlatform(),
  platform: () => {
    const platform = Capacitor.getPlatform()
    return platform === 'ios' || platform === 'android' ? platform : 'web'
  },
  hasRuntime: () => Capacitor.isPluginAvailable('HostRuntime'),
}

/** Inbound application links and installed build metadata. */
export const hostApplication: HostApplication = {
  getInfo: () => App.getInfo(),
  getLaunchUrl: () => App.getLaunchUrl(),
  addListener: (event, handler) => App.addListener(event, handler),
}

/** Browser transport preserving native dismissal and completion events. */
export const hostBrowser: HostBrowser = {
  open: options => Browser.open(options),
  close: () => Browser.close(),
  addListener: (event, handler) => event === 'browserFinished'
    ? Browser.addListener('browserFinished', handler)
    : Browser.addListener('browserPageLoaded', handler),
  removeAllListeners: () => Browser.removeAllListeners(),
}

/** Map semantic feedback to the current native plugin. */
export const hostHaptics: HostHaptics = {
  impact: ({ style }) => Haptics.impact({ style: {
    light: ImpactStyle.Light,
    medium: ImpactStyle.Medium,
    heavy: ImpactStyle.Heavy,
  }[style] }),
  notification: ({ type }) => Haptics.notification({ type: {
    success: NotificationType.Success,
    warning: NotificationType.Warning,
    error: NotificationType.Error,
  }[type] }),
  vibrate: options => Haptics.vibrate(options),
}

let runtime: HostRuntimePlugin | undefined

function getRuntime(): HostRuntimePlugin {
  runtime ??= registerPlugin<HostRuntimePlugin>('HostRuntime')
  return runtime
}

/** Runtime operations keep transport registration out of business modules. */
export const HostRuntime: HostRuntimePlugin = {
  open: options => getRuntime().open(options),
  close: () => getRuntime().close(),
  updateAppInfo: options => getRuntime().updateAppInfo(options),
  configureSessionPolicy: options => getRuntime().configureSessionPolicy(options),
  resumeSession: options => getRuntime().resumeSession(options),
  listSessions: () => getRuntime().listSessions(),
  endSession: options => getRuntime().endSession(options),
  confirmAuthorization: options => getRuntime().confirmAuthorization(options),
  requestHostLogin: options => getRuntime().requestHostLogin(options),
  resumeAuthorizationAfterLogin: options => getRuntime().resumeAuthorizationAfterLogin(options),
  cancelAuthorizationLogin: options => getRuntime().cancelAuthorizationLogin(options),
  authorizeWithOtherAccount: options => getRuntime().authorizeWithOtherAccount(options),
  resolveAuthorization: options => getRuntime().resolveAuthorization(options),
  clearIdentitySessions: () => getRuntime().clearIdentitySessions(),
  addListener: (event, handler) => getRuntime().addListener(event, handler),
  removeAllListeners: () => getRuntime().removeAllListeners(),
}

/**
 * Present the native scanner with the shared accessible controls.
 * @returns The decoded barcode and its format.
 */
export async function scanNativeBarcode(): Promise<NativeBarcodeResult> {
  const { CapacitorBarcodeScanner, CapacitorBarcodeScannerCameraDirection, CapacitorBarcodeScannerTypeHintALLOption } = await import('@capacitor/barcode-scanner')
  return CapacitorBarcodeScanner.scanBarcode({
    hint: CapacitorBarcodeScannerTypeHintALLOption.ALL,
    cameraDirection: CapacitorBarcodeScannerCameraDirection.BACK,
    scanInstructions: '将二维码或条形码放入框内',
    cancelButtonAccessibilityLabel: '取消扫码',
    torchButtonOnAccessibilityLabel: '关闭手电筒',
    torchButtonOffAccessibilityLabel: '打开手电筒',
  })
}

/**
 * Pick a single photo without exposing camera plugin types to the scan flow.
 * @returns A WebView-readable image URL, or null when the picker has no result.
 */
export async function pickNativePhoto(): Promise<string | null> {
  const { Camera, MediaTypeSelection } = await import('@capacitor/camera')
  const { results } = await Camera.chooseFromGallery({
    mediaType: MediaTypeSelection.Photo,
    allowMultipleSelection: false,
    editable: 'no',
    quality: 100,
    correctOrientation: true,
    presentationStyle: 'fullscreen',
  })
  return results[0]?.webPath ?? null
}
