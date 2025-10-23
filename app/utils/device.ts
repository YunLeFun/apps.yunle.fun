/**
 * 设备检测工具函数
 */

/**
 * 检测是否为移动端设备
 * @returns {boolean} 是否为移动端设备
 */
export function isMobile(): boolean {
  if (typeof window === 'undefined') {
    return false
  }

  const userAgent = navigator.userAgent.toLowerCase()
  const mobileKeywords = ['android', 'iphone', 'ipad', 'ipod', 'blackberry', 'windows phone', 'mobile']

  return mobileKeywords.some(keyword => userAgent.includes(keyword))
    || (window.innerWidth <= 768 && 'ontouchstart' in window)
}

/**
 * 检测是否为平板设备
 * @returns {boolean} 是否为平板设备
 */
export function isTablet(): boolean {
  if (typeof window === 'undefined') {
    return false
  }

  const userAgent = navigator.userAgent.toLowerCase()
  const screenWidth = window.innerWidth

  return userAgent.includes('ipad')
    || (userAgent.includes('android') && !userAgent.includes('mobile'))
    || (screenWidth > 768 && screenWidth <= 1024 && 'ontouchstart' in window)
}

/**
 * 检测是否为桌面端设备
 * @returns {boolean} 是否为桌面端设备
 */
export function isDesktop(): boolean {
  return !isMobile() && !isTablet()
}

/**
 * 获取设备类型
 * @returns {'mobile' | 'tablet' | 'desktop'} 设备类型
 */
export function getDeviceType(): 'mobile' | 'tablet' | 'desktop' {
  if (isMobile())
    return 'mobile'
  if (isTablet())
    return 'tablet'
  return 'desktop'
}
