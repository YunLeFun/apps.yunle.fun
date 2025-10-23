import { acceptHMRUpdate, defineStore } from 'pinia'

export interface UserInfo {
  avatar: string
  nickname: string
}

const defaultUserInfo: UserInfo = {
  avatar: '',
  nickname: '',
}

export const userInfo = ref<UserInfo>(JSON.parse(JSON.stringify(defaultUserInfo)))

export const useUserStore = defineStore('user', () => {
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

  return {
    userInfo,

    setNewName,
    otherNames,
    savedName,

    setUserInfo,
  }
})

if (import.meta.hot)
  import.meta.hot.accept(acceptHMRUpdate(useUserStore, import.meta.hot))
