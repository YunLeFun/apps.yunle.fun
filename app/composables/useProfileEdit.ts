import { actionSheetController, alertController } from '@ionic/vue'

export function useProfileEdit() {
  const toast = useToast()

  const {
    user,
    loading: authLoading,
    fetchUser,
    updateUserInfo,
    unlinkProvider,
    linkProvider,
    resetPasswordWithOld,
    changeEmail,
    verifyEmailBindOtp,
  } = useCloudbaseAuth()

  // === 计算属性 ===
  const displayName = computed(() =>
    user.value?.nickname || userInfo.value.nickname || '未设置',
  )
  const displayDescription = computed(() => user.value?.description || '')
  const displayPhone = computed(() => {
    const phone = user.value?.phone
    if (!phone)
      return '未绑定'
    return phone.replace(/(\d{3})\d{4}(\d{4})/, '$1****$2')
  })
  const displayEmail = computed(() => user.value?.email || '未绑定')
  const joinDate = computed(() => {
    const date = user.value?.createdAt
    if (!date)
      return '未知'
    return new Date(date).toLocaleDateString('zh-CN', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    })
  })
  const avatarInitial = computed(() => (displayName.value || '云').charAt(0))
  const isGitHubBound = computed(() => user.value?.providers?.includes('github'))
  const isWeChatBound = computed(() => user.value?.providers?.includes('wx_open'))
  const isPhoneBound = computed(() => !!user.value?.phone)
  const isEmailBound = computed(() => !!user.value?.email)
  const hasPassword = computed(() => user.value?.hasPassword ?? false)
  const displayGender = computed(() => {
    const g = user.value?.gender
    if (g === 'MALE')
      return '男'
    if (g === 'FEMALE')
      return '女'
    return '未设置'
  })

  // === 编辑昵称 ===
  async function editNickname() {
    const alert = await alertController.create({
      header: '修改昵称',
      inputs: [
        {
          name: 'nickname',
          type: 'text',
          placeholder: '请输入昵称',
          value: user.value?.nickname || '',
          attributes: { maxlength: 20 },
        },
      ],
      buttons: [
        { text: '取消', role: 'cancel' },
        {
          text: '完成',
          handler: async (data) => {
            const val = data.nickname?.trim()
            if (!val || val === (user.value?.nickname || ''))
              return
            await updateUserInfo({ nickname: val } as any)
          },
        },
      ],
    })
    await alert.present()
  }

  // === 编辑性别 ===
  async function editGender() {
    const actionSheet = await actionSheetController.create({
      header: '选择性别',
      buttons: [
        {
          text: '男',
          handler: () => updateUserInfo({ gender: 'MALE' } as any),
        },
        {
          text: '女',
          handler: () => updateUserInfo({ gender: 'FEMALE' } as any),
        },
        {
          text: '未设置',
          handler: () => updateUserInfo({ gender: '' } as any),
        },
        { text: '取消', role: 'cancel' },
      ],
    })
    await actionSheet.present()
  }

  // === 手机号提示 ===
  function handlePhoneTap() {
    toast.showInfo('手机号暂不支持换绑')
  }

  // === 绑定/解绑微信 ===
  async function handleWeChatTap() {
    if (isWeChatBound.value) {
      const alert = await alertController.create({
        header: '解绑微信',
        message: '确定要解绑微信账号吗？解绑后将无法通过微信登录。',
        buttons: [
          { text: '取消', role: 'cancel' },
          {
            text: '解绑',
            role: 'destructive',
            handler: () => unlinkProvider('wx_open'),
          },
        ],
      })
      await alert.present()
    }
    else {
      await linkProvider('wx_open')
    }
  }

  // === 绑定/解绑 GitHub ===
  async function handleGitHubTap() {
    if (isGitHubBound.value) {
      const alert = await alertController.create({
        header: '解绑 GitHub',
        message: '确定要解绑 GitHub 账号吗？解绑后将无法通过 GitHub 登录。',
        buttons: [
          { text: '取消', role: 'cancel' },
          {
            text: '解绑',
            role: 'destructive',
            handler: () => unlinkProvider('github'),
          },
        ],
      })
      await alert.present()
    }
    else {
      await linkProvider('github')
    }
  }

  // === 工具 ===
  async function copyToClipboard(text: string) {
    try {
      await navigator.clipboard.writeText(text)
      toast.showSuccess('已复制')
    }
    catch { /* silent */ }
  }

  async function handleRefresh() {
    await fetchUser()
    toast.showSuccess('已刷新')
  }

  return {
    // 状态
    user,
    authLoading,
    // 计算属性
    displayName,
    displayDescription,
    displayPhone,
    displayEmail,
    displayGender,
    joinDate,
    avatarInitial,
    isGitHubBound,
    isWeChatBound,
    isPhoneBound,
    isEmailBound,
    hasPassword,
    // 操作方法
    fetchUser,
    editNickname,
    editGender,
    handlePhoneTap,
    handleWeChatTap,
    handleGitHubTap,
    copyToClipboard,
    handleRefresh,
    // Modal 子组件需要的 auth 方法
    updateUserInfo,
    changeEmail,
    verifyEmailBindOtp,
    resetPasswordWithOld,
  }
}
