import type { AppRecord, CreateAppForm } from '~/types/app'
import { actionSheetController } from '@ionic/vue'
import { onBeforeRouteLeave } from 'vue-router'
import { DEFAULT_EMOJI, DEFAULT_THEME_COLOR } from '~/types/app'

const DRAFT_KEY = 'app_create_draft'
const SLUG_REGEX = /^[a-z][a-z0-9-]{1,49}$/
const TAGS_SPLIT_REGEX = /[,，、\s]+/
const NON_SLUG_CHARS_REGEX = /[^a-z0-9\u4E00-\u9FFF-]/g
const MULTIPLE_HYPHENS_REGEX = /-+/g
const LEADING_TRAILING_HYPHENS_REGEX = /^-|-$/g

function createEmptyForm() {
  return {
    name: '',
    slug: '',
    description: '',
    githubRepo: '',
    websiteUrl: '',
    backupUrl: '',
    logo: '',
    emoji: DEFAULT_EMOJI,
    themeColor: DEFAULT_THEME_COLOR,
    category: '',
    tags: [] as string[],
    // 默认不公开 —— 用户提交后即使勾了 isPublic，也需要审核通过才会真对外可见
    // 详见 app/types/app.ts AppStatus
    isPublic: false,
  }
}

export type AppFormData = ReturnType<typeof createEmptyForm>

/**
 * 应用表单 composable
 * @param mode 'create' | 'edit'
 * @param existingApp 编辑模式下的已有应用数据
 */
export function useAppForm(mode: 'create' | 'edit' = 'create', existingApp?: Ref<AppRecord | null>) {
  const router = useRouter()
  const toast = useToast()
  const userStore = useUserStore()
  const { createApp, updateApp, isSlugTaken } = useApps()

  const form = reactive(createEmptyForm())
  const saving = ref(false)
  const slugError = ref('')
  const slugChecking = ref(false)
  const submitted = ref(false)
  const autoSlug = ref(mode === 'create')

  // dirty 检测
  const initialFormSnapshot = ref(JSON.stringify(createEmptyForm()))
  const isDirty = computed(() => JSON.stringify(form) !== initialFormSnapshot.value)

  /** 用已有数据填充表单 */
  function populateForm(app: AppRecord) {
    form.name = app.name
    form.slug = app.slug
    form.description = app.description || ''
    form.githubRepo = app.githubRepo || ''
    form.websiteUrl = app.websiteUrl || ''
    form.backupUrl = app.backupUrl || ''
    form.logo = app.logo || ''
    form.emoji = app.emoji || DEFAULT_EMOJI
    form.themeColor = app.themeColor || DEFAULT_THEME_COLOR
    form.category = app.category || ''
    form.tags = app.tags ? [...app.tags] : []
    form.isPublic = app.isPublic
    autoSlug.value = false
    // 更新初始快照
    initialFormSnapshot.value = JSON.stringify(form)
  }

  // 编辑模式：监听 existingApp 变化自动填充
  if (mode === 'edit' && existingApp) {
    watch(existingApp, (app) => {
      if (app)
        populateForm(app)
    }, { immediate: true })
  }

  // ---- 草稿管理（仅创建模式） ----

  function restoreDraft() {
    if (mode !== 'create')
      return

    try {
      const raw = localStorage.getItem(DRAFT_KEY)

      if (!raw)
        return

      const draft = JSON.parse(raw)
      // 兼容旧版 tags 为字符串的情况
      if (typeof draft.tags === 'string') {
        draft.tags = draft.tags.split(TAGS_SPLIT_REGEX).map((t: string) => t.trim()).filter(Boolean)
      }
      Object.assign(form, draft)
      toast.showSuccess('已恢复上次的草稿')
    }
    catch {
      localStorage.removeItem(DRAFT_KEY)
    }
  }

  function saveDraft() {
    localStorage.setItem(DRAFT_KEY, JSON.stringify(form))
  }

  function clearDraft() {
    localStorage.removeItem(DRAFT_KEY)
  }

  onMounted(() => {
    restoreDraft()
  })

  // ---- 路由离开守卫 ----

  onBeforeRouteLeave(async () => {
    if (submitted.value || !isDirty.value)
      return true

    // 用 Promise 等待 ActionSheet 结果，避免 handler 异步导致路由不跳转
    let sheet: HTMLIonActionSheetElement | undefined
    const result = await new Promise<'save' | 'discard' | 'cancel'>((resolve) => {
      const buttons = mode === 'create'
        ? [
            {
              text: '存为草稿',
              handler: () => { resolve('save') },
            },
            {
              text: '丢弃',
              role: 'destructive' as const,
              handler: () => { resolve('discard') },
            },
            {
              text: '继续编辑',
              role: 'cancel' as const,
              handler: () => { resolve('cancel') },
            },
          ]
        : [
            {
              text: '放弃修改',
              role: 'destructive' as const,
              handler: () => { resolve('discard') },
            },
            {
              text: '继续编辑',
              role: 'cancel' as const,
              handler: () => { resolve('cancel') },
            },
          ]

      actionSheetController.create({
        header: '你有未保存的修改',
        buttons,
      }).then((s) => {
        sheet = s
        s.present()
      })
    })
    // 确保 ActionSheet 已关闭
    await sheet?.dismiss()

    if (result === 'save') {
      saveDraft()
      toast.showSuccess('草稿已保存')
      return true
    }
    if (result === 'discard') {
      clearDraft()
      return true
    }
    return false
  })

  // ---- Slug 校验 ----

  let slugCheckTimer: ReturnType<typeof setTimeout> | null = null

  function checkSlugAvailability(slug: string) {
    if (slugCheckTimer)
      clearTimeout(slugCheckTimer)

    if (!slug) {
      slugError.value = ''
      return
    }
    if (!SLUG_REGEX.test(slug)) {
      slugError.value = '以小写字母开头，只含小写字母、数字和连字符，2-50 字符'
      return
    }

    // 编辑模式下如果 slug 没变，跳过唯一性检查
    if (mode === 'edit' && existingApp?.value?.slug === slug) {
      slugError.value = ''
      return
    }

    slugError.value = ''
    slugChecking.value = true

    slugCheckTimer = setTimeout(async () => {
      try {
        const taken = await isSlugTaken(slug)
        if (form.slug === slug) {
          slugChecking.value = false
          slugError.value = taken ? '此标识符已被占用，请换一个' : ''
        }
      }
      catch {
        slugChecking.value = false
      }
    }, 500)
  }

  watch(() => form.name, (name) => {
    if (autoSlug.value) {
      const slug = name
        .toLowerCase()
        .replace(NON_SLUG_CHARS_REGEX, '-')
        .replace(MULTIPLE_HYPHENS_REGEX, '-')
        .replace(LEADING_TRAILING_HYPHENS_REGEX, '')
        .slice(0, 50)
      form.slug = slug
      checkSlugAvailability(slug)
    }
  })

  watch(() => form.slug, (slug) => {
    if (!autoSlug.value) {
      checkSlugAvailability(slug)
    }
  })

  function onSlugInput() {
    autoSlug.value = false
  }

  // ---- 提交 ----

  function buildFormData(): CreateAppForm {
    return {
      name: form.name.trim(),
      slug: form.slug,
      description: form.description.trim(),
      githubRepo: form.githubRepo.trim(),
      websiteUrl: form.websiteUrl.trim(),
      backupUrl: form.backupUrl.trim(),
      logo: form.logo.trim(),
      emoji: form.emoji || DEFAULT_EMOJI,
      themeColor: form.themeColor || DEFAULT_THEME_COLOR,
      category: form.category,
      tags: form.tags.filter(Boolean),
      isPublic: form.isPublic,
    }
  }

  async function handleSubmit() {
    if (!userStore.isLoggedIn) {
      toast.showWarning('请先登录')
      router.push('/login')
      return
    }

    if (!form.name.trim()) {
      toast.showWarning('请输入应用名称')
      return
    }

    if (!SLUG_REGEX.test(form.slug)) {
      slugError.value = '以小写字母开头，只含小写字母、数字和连字符，2-50 字符'
      return
    }

    if (slugError.value)
      return

    try {
      saving.value = true
      const workshopDirty = useState('workshop:dirty', () => false)

      if (mode === 'create') {
        const taken = await isSlugTaken(form.slug)
        if (taken) {
          slugError.value = '此标识符已被占用，请换一个'
          return
        }
        await createApp(buildFormData())
        submitted.value = true
        clearDraft()
        workshopDirty.value = true
        toast.showSuccess('应用创建成功')
        router.push('/workshop')
      }
      else {
        // 编辑模式
        if (!existingApp?.value)
          return

        // slug 变更时需要检查唯一性
        if (form.slug !== existingApp.value.slug) {
          const taken = await isSlugTaken(form.slug)
          if (taken) {
            slugError.value = '此标识符已被占用，请换一个'
            return
          }
        }
        await updateApp(existingApp.value._id, buildFormData())
        submitted.value = true
        workshopDirty.value = true
        toast.showSuccess('保存成功')
        // 更新快照
        initialFormSnapshot.value = JSON.stringify(form)
        // 返回详情页（使用可能已更新的 slug）
        router.replace(`/workshop/${form.slug}`)
      }
    }
    catch (err: unknown) {
      toast.showError(err instanceof Error ? err.message : `${mode === 'create' ? '创建' : '保存'}失败，请稍后重试`)
    }
    finally {
      saving.value = false
    }
  }

  return {
    form,
    saving,
    slugError,
    slugChecking,
    isDirty,
    SLUG_REGEX,
    onSlugInput,
    handleSubmit,
    populateForm,
  }
}
