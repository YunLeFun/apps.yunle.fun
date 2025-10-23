import { acceptHMRUpdate, defineStore } from 'pinia'

export interface UserInfo {
  avatar: string
  nickname: string
}

// 扩展的用户信息接口，用于 profile 页面
export interface ExtendedUserInfo {
  openid: string
  nickname: string
  sex: 1 | 2 | 0
  province: string
  city: string
  country: string
  headimgurl: string
  privilege: string[]
  unionid?: string
}

export interface UserSession {
  accessToken: string
  user: UserInfo
}

const defaultUserInfo: UserInfo = {
  avatar: '',
  nickname: '',
}

export const userInfo = ref<UserInfo>(JSON.parse(JSON.stringify(defaultUserInfo)))

export const useUserStore = defineStore('user', () => {
  // 使用 Cookie 存储 JWT token（最佳实践）
  const accessToken = useCookie<string>('ylf_access_token', {
    default: () => '',
    maxAge: 60 * 60 * 24 * 7, // 7 天过期
    sameSite: 'strict', // 防止 CSRF
    secure: import.meta.env.PROD, // 生产环境使用 HTTPS
    httpOnly: false, // 客户端需要访问，设为 false
  })

  // 使用 Cookie 存储用户信息（可选，也可以只存 token）
  const userInfoCookie = useCookie<UserInfo>('ylf_user_info', {
    default: () => defaultUserInfo,
    maxAge: 60 * 60 * 24 * 7,
    sameSite: 'strict',
    secure: import.meta.env.PROD,
  })

  // 同步 cookie 和响应式状态
  watch(userInfoCookie, (newValue) => {
    userInfo.value = newValue
  }, { immediate: true })

  watch(userInfo, (newValue) => {
    userInfoCookie.value = newValue
  })

  const isLoggedIn = computed(() => !!accessToken.value && !!userInfo.value.nickname)

  /**
   * Current named of the user.
   */
  const savedName = ref('')
  const previousNames = ref(new Set<string>())

  const usedNames = computed(() => Array.from(previousNames.value))
  const otherNames = computed(() => usedNames.value.filter(name => name !== savedName.value))

  /**
   * Changes the current name of the user and saves the one that was used
   * before.
   *
   * @param name - new name to set
   */
  function setNewName(name: string) {
    if (savedName.value)
      previousNames.value.add(savedName.value)

    savedName.value = name
  }

  function setUserInfo(info: UserInfo) {
    userInfo.value = info
  }

  /**
   * 登录：保存 access_token 和用户信息
   */
  function login(token: string, user: UserInfo) {
    accessToken.value = token
    userInfo.value = user
    // userInfoCookie 会通过 watch 自动同步
  }

  /**
   * 登出：清除 token 和用户信息
   */
  function logout() {
    accessToken.value = ''
    userInfo.value = JSON.parse(JSON.stringify(defaultUserInfo))
    // Cookie 会自动清除
  }

  return {
    userInfo,
    accessToken,
    isLoggedIn,

    setNewName,
    otherNames,
    savedName,

    setUserInfo,
    login,
    logout,
  }
})

if (import.meta.hot)
  import.meta.hot.accept(acceptHMRUpdate(useUserStore, import.meta.hot))
