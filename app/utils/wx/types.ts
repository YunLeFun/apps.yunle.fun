export interface WxUserInfo {
  /**
   * 用户的唯一标识
   */
  openid: string
  /**
   * 用户昵称
   */
  nickname: string
  /**
   * 用户的性别，值为1时是男性，值为2时是女性，值为0时是未知
   */
  sex: 1 | 2 | 0
  /**
   * 用户个人资料填写的省份
   */
  province: string
  /**
   * 普通用户个人资料填写的城市
   */
  city: string
  /**
   * 国家，如中国为CN
   */
  country: string
  /**
   * 用户头像，最后一个数值代表正方形头像大小（有0、46、64、96、132数值可选，0代表640*640正方形头像），用户没有头像时该项为空。若用户更换头像，原有头像URL将失效。
   */
  headimgurl: string
  /**
   * 用户特权信息，json 数组，如微信沃卡用户为（chinaunicom）
   */
  privilege: string[]
  /**
   * 只有在用户将公众号绑定到微信开放平台账号后，才会出现该字段。
   */
  unionid: string
}
