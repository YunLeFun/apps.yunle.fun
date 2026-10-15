import type { AcquisitionContext } from '~/utils/acquisition'

const touch = {
  capturedAt: 1000,
  landingHost: 'cook.yunle.fun',
  landingPath: '/random',
  referrerHost: 'www.baidu.com',
  utmSource: 'baidu',
  utmMedium: 'organic',
  utmCampaign: '',
}
export const acquisition: AcquisitionContext = { version: 1, firstTouch: touch, registerTouch: touch }
