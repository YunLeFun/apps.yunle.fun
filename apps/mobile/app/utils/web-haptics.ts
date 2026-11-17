/** Vibration is optional in browsers and can be denied by the device or user. */
export function vibrate(duration = 12) {
  if (typeof navigator !== 'undefined')
    navigator.vibrate?.(duration)
}
