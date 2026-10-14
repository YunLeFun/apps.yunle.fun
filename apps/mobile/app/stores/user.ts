import type { YlfUserInfo } from '@yunlefun/auth'
import { Capacitor } from '@capacitor/core'
import { acceptHMRUpdate, defineStore } from 'pinia'

export type UserInfo = YlfUserInfo

const TOKEN_KEY = 'ylf_access_token'
const USER_INFO_KEY = 'ylf_user_info'

export interface UserSession {
  accessToken: string
  user: UserInfo
}

const defaultUserInfo: YlfUserInfo = {
  avatar: '',
  nickname: '',
}

export const userInfo = ref<YlfUserInfo>(JSON.parse(JSON.stringify(defaultUserInfo)))

export const useUserStore = defineStore('user', () => {
  // 原生壳内 origin 是 capacitor://localhost（非 HTTPS），带 Secure 标记的 cookie
  // 可能被 WebKit 拒写；且 WKWebView 对自定义 scheme 的 cookie 持久化不可靠
  const isNativeShell = import.meta.client && Capacitor.isNativePlatform()

  // 使用 Cookie 存储 JWT token（Web 端 SSR 友好）
  const accessToken = useCookie<string>(TOKEN_KEY, {
    default: () => '',
    maxAge: 60 * 60 * 24 * 31, // 31 天过期（与 refresh token 有效期对齐）
    sameSite: 'strict', // 防止 CSRF
    secure: import.meta.env.PROD && !isNativeShell, // 生产环境使用 HTTPS；原生壳非 HTTPS 上下文
    httpOnly: false, // 客户端需要访问，设为 false
  })

  // 使用 Cookie 存储用户信息（可选，也可以只存 token）
  const userInfoCookie = useCookie<YlfUserInfo>(USER_INFO_KEY, {
    default: () => defaultUserInfo,
    maxAge: 60 * 60 * 24 * 31, // 31 天过期
    sameSite: 'strict',
    secure: import.meta.env.PROD && !isNativeShell,
  })
  // cookie 丢失（原生壳重启/更新后常见）时从 localStorage 镜像恢复，
  // 与 CloudBase SDK 凭证（persistence: 'local'，同在 localStorage）同生共死
  if (import.meta.client) {
    try {
      if (!accessToken.value) {
        const stored = localStorage.getItem(TOKEN_KEY)
        if (stored)
          accessToken.value = stored
      }
      if (!userInfoCookie.value?.nickname) {
        const stored = localStorage.getItem(USER_INFO_KEY)
        if (stored)
          userInfoCookie.value = JSON.parse(stored)
      }
      // 删除旧版临时验证码流程留下的宿主 capability；固定测试账号现已使用标准会话。
      localStorage.removeItem('ylf_native_test_session')
    }
    catch {
      // localStorage 不可用或镜像数据损坏时忽略，仅依赖 cookie
    }

    // 只写入、不删除：token 变空可能是 cookie 被外部清掉（WKWebView 等），
    // 不能据此删镜像；镜像仅在显式 logout 时清除
    watch(accessToken, (token) => {
      if (!token)
        return
      try {
        localStorage.setItem(TOKEN_KEY, token)
      }
      catch {}
    }, { immediate: true })
  }

  // 同步 cookie 和响应式状态
  watch(userInfoCookie, (newValue) => {
    userInfo.value = newValue
  }, { immediate: true })

  watch(userInfo, (newValue) => {
    userInfoCookie.value = newValue
  })

  // userInfo → localStorage 镜像（immediate：启动时为存量登录态补写镜像）
  // 同样只写入、不删除，清除统一收口在 logout
  if (import.meta.client) {
    watch(userInfo, (newValue) => {
      if (!newValue?.nickname)
        return
      try {
        localStorage.setItem(USER_INFO_KEY, JSON.stringify(newValue))
      }
      catch {}
    }, { immediate: true })
  }

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

  function setUserInfo(info: YlfUserInfo) {
    userInfo.value = info
  }

  /**
   * 登录：保存 access_token 和用户信息
   */
  function login(token: string, user: YlfUserInfo) {
    accessToken.value = token
    userInfo.value = user
    // userInfoCookie 会通过 watch 自动同步
  }

  /**
   * 登出：清除 token、用户信息及 localStorage 镜像
   */
  function logout() {
    accessToken.value = ''
    userInfo.value = JSON.parse(JSON.stringify(defaultUserInfo))
    // Cookie 会自动清除；镜像仅在此处显式清除
    if (import.meta.client) {
      try {
        localStorage.removeItem(TOKEN_KEY)
        localStorage.removeItem(USER_INFO_KEY)
      }
      catch {}
    }
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
