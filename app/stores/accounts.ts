import type { YlfUserInfo } from '@yunlefun/auth'
import { acceptHMRUpdate, defineStore } from 'pinia'

/**
 * 已保存的账号信息
 */
export interface SavedAccount {
  /** 用户 ID（CloudBase uid） */
  uid: string
  /** 昵称 */
  nickname: string
  /** 头像 */
  avatar: string
  /** 手机号（脱敏） */
  phone?: string
  /** 邮箱（脱敏） */
  email?: string
  /** 上次登录时间（ISO string） */
  lastLoginAt: string
  /** 上次使用的登录方式 */
  lastLoginMethod?: 'phone' | 'email' | 'password' | 'github' | 'wechat'
}

const STORAGE_KEY = 'ylf_saved_accounts'
const LAST_PHONE_KEY = 'ylf_last_phone'
/** 已保存账号的最大数量 */
const MAX_ACCOUNTS = 10

/**
 * 脱敏手机号：138****1234
 */
function maskPhone(phone: string): string {
  if (!phone || phone.length < 7)
    return phone
  return `${phone.slice(0, 3)}****${phone.slice(-4)}`
}

/**
 * 脱敏邮箱：ab***@example.com
 */
function maskEmail(email: string): string {
  if (!email)
    return email
  const [local, domain] = email.split('@')
  if (!local || !domain)
    return email
  const visible = local.slice(0, 2)
  return `${visible}***@${domain}`
}

/**
 * 简单混淆手机号（base64），避免 localStorage 明文存储
 * 注意：这不是加密，仅防止被直接肉眼读取
 */
function obfuscate(value: string): string {
  if (!value)
    return ''
  return btoa(encodeURIComponent(value))
}

function deobfuscate(value: string): string {
  if (!value)
    return ''
  try {
    return decodeURIComponent(atob(value))
  }
  catch {
    return ''
  }
}

export const useAccountsStore = defineStore('accounts', () => {
  /** 已保存的账号列表 */
  const accounts = ref<SavedAccount[]>([])

  /** 上次使用的手机号（完整，未脱敏） */
  const lastPhone = ref('')

  /** 从 localStorage 加载 */
  function load() {
    if (!import.meta.client)
      return
    try {
      const raw = localStorage.getItem(STORAGE_KEY)
      if (raw) {
        const parsed = JSON.parse(raw)
        accounts.value = Array.isArray(parsed) ? parsed.slice(0, MAX_ACCOUNTS) : []
      }
    }
    catch {
      accounts.value = []
    }
    lastPhone.value = deobfuscate(localStorage.getItem(LAST_PHONE_KEY) || '')
  }

  /** 持久化到 localStorage */
  function save() {
    if (!import.meta.client)
      return
    localStorage.setItem(STORAGE_KEY, JSON.stringify(accounts.value.slice(0, MAX_ACCOUNTS)))
    localStorage.setItem(LAST_PHONE_KEY, obfuscate(lastPhone.value))
  }

  /** 初始化加载 */
  load()

  /**
   * 登录成功后保存/更新账号
   */
  function saveAccount(userInfo: YlfUserInfo, loginMethod?: SavedAccount['lastLoginMethod']) {
    if (!userInfo.id)
      return

    const idx = accounts.value.findIndex(a => a.uid === userInfo.id)
    const account: SavedAccount = {
      uid: userInfo.id,
      nickname: userInfo.nickname || '',
      avatar: userInfo.avatar || '',
      phone: userInfo.phone ? maskPhone(userInfo.phone) : undefined,
      email: userInfo.email ? maskEmail(userInfo.email) : undefined,
      lastLoginAt: new Date().toISOString(),
      lastLoginMethod: loginMethod,
    }

    if (idx >= 0) {
      accounts.value[idx] = account
    }
    else {
      accounts.value.unshift(account)
      // 限制最大保存数量
      if (accounts.value.length > MAX_ACCOUNTS)
        accounts.value = accounts.value.slice(0, MAX_ACCOUNTS)
    }

    save()
  }

  /**
   * 记住手机号（完整号码，不脱敏）
   */
  function rememberPhone(phone: string) {
    lastPhone.value = phone
    save()
  }

  /**
   * 删除已保存的账号
   */
  function removeAccount(uid: string) {
    accounts.value = accounts.value.filter(a => a.uid !== uid)
    save()
  }

  /**
   * 清除所有已保存的账号
   */
  function clearAll() {
    accounts.value = []
    lastPhone.value = ''
    save()
  }

  /**
   * 获取除当前用户外的其他账号
   */
  function getOtherAccounts(currentUid?: string) {
    if (!currentUid)
      return accounts.value
    return accounts.value.filter(a => a.uid !== currentUid)
  }

  return {
    accounts,
    lastPhone,
    saveAccount,
    rememberPhone,
    removeAccount,
    clearAll,
    getOtherAccounts,
  }
})

if (import.meta.hot)
  import.meta.hot.accept(acceptHMRUpdate(useAccountsStore, import.meta.hot))
