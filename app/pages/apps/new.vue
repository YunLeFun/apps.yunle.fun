<script setup lang="ts">
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonInput,
  IonItem,
  IonLabel,
  IonList,
  IonNote,
  IonPage,
  IonTextarea,
  IonTitle,
  IonToggle,
  IonToolbar,
} from '@ionic/vue'
import { checkmark } from 'ionicons/icons'

const router = useRouter()
const toast = useToast()
const { user } = useCloudbaseAuth()
const { createApp, isSlugTaken } = useApps()

const saving = ref(false)
const slugError = ref('')

const form = reactive({
  name: '',
  slug: '',
  description: '',
  githubRepo: '',
  websiteUrl: '',
  backupUrl: '',
  category: '',
  tags: '',
  isPublic: true,
})

// 根据名称自动生成 slug
const autoSlug = ref(true)

watch(() => form.name, (name) => {
  if (autoSlug.value) {
    form.slug = name
      .toLowerCase()
      .replace(/[^a-z0-9\u4E00-\u9FFF-]/g, '-')
      .replace(/-+/g, '-')
      .replace(/^-|-$/g, '')
      .slice(0, 50)
  }
})

function onSlugInput() {
  autoSlug.value = false
  slugError.value = ''
}

const SLUG_REGEX = /^[a-z][a-z0-9-]{1,49}$/

async function handleSubmit() {
  if (!user.value) {
    toast.show('请先登录', 'warning')
    router.push('/login')
    return
  }

  if (!form.name.trim()) {
    toast.show('请输入应用名称', 'warning')
    return
  }

  if (!SLUG_REGEX.test(form.slug)) {
    slugError.value = '以小写字母开头，只含小写字母、数字和连字符，2-50 字符'
    return
  }

  try {
    saving.value = true

    const taken = await isSlugTaken(form.slug)
    if (taken) {
      slugError.value = '此标识符已被使用'
      return
    }

    const tags = form.tags
      .split(/[,，、\s]+/)
      .map(t => t.trim())
      .filter(Boolean)

    await createApp({
      name: form.name.trim(),
      slug: form.slug,
      description: form.description.trim(),
      githubRepo: form.githubRepo.trim(),
      websiteUrl: form.websiteUrl.trim(),
      backupUrl: form.backupUrl.trim(),
      category: form.category.trim(),
      tags,
      isPublic: form.isPublic,
    })

    toast.show('应用创建成功', 'success')
    router.push('/apps/my')
  }
  catch (err: unknown) {
    toast.show(err instanceof Error ? err.message : '创建失败，请稍后重试', 'error')
  }
  finally {
    saving.value = false
  }
}
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/apps/my" text="返回" />
        </IonButtons>
        <IonTitle>创建应用</IonTitle>
        <IonButtons slot="end">
          <IonButton :disabled="saving || !form.name.trim()" @click="handleSubmit">
            <IonIcon v-if="!saving" slot="icon-only" :icon="checkmark" />
            <span v-else class="text-sm">保存中...</span>
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true" class="ion-padding">
      <form @submit.prevent="handleSubmit">
        <!-- 基本信息 -->
        <IonList inset>
          <IonItem>
            <IonInput
              v-model="form.name"
              label="应用名称"
              label-placement="stacked"
              placeholder="输入应用名称"
              :maxlength="50"
              required
            />
          </IonItem>

          <IonItem :class="{ 'ion-invalid': slugError }">
            <IonInput
              v-model="form.slug"
              label="标识符"
              label-placement="stacked"
              placeholder="my-app"
              :maxlength="50"
              class="font-mono"
              @ion-input="onSlugInput"
            />
            <IonNote v-if="slugError" slot="error" color="danger">
              {{ slugError }}
            </IonNote>
            <IonNote v-else slot="helper">
              唯一标识，用于 URL
            </IonNote>
          </IonItem>

          <IonItem>
            <IonTextarea
              v-model="form.description"
              label="简介"
              label-placement="stacked"
              placeholder="简短描述你的应用..."
              :rows="3"
              :maxlength="300"
              :auto-grow="true"
            />
          </IonItem>
        </IonList>

        <!-- 链接信息 -->
        <IonList inset>
          <IonItem>
            <IonInput
              v-model="form.websiteUrl"
              label="网址"
              label-placement="stacked"
              placeholder="https://example.com"
              type="url"
            />
          </IonItem>

          <IonItem>
            <IonInput
              v-model="form.githubRepo"
              label="GitHub 仓库"
              label-placement="stacked"
              placeholder="owner/repo"
            />
            <IonNote slot="helper">
              格式：owner/repo
            </IonNote>
          </IonItem>

          <IonItem>
            <IonInput
              v-model="form.backupUrl"
              label="备用链接"
              label-placement="stacked"
              placeholder="https://mirror.example.com"
              type="url"
            />
          </IonItem>
        </IonList>

        <!-- 分类与标签 -->
        <IonList inset>
          <IonItem>
            <IonInput
              v-model="form.category"
              label="分类"
              label-placement="stacked"
              placeholder="如：工具、应用、整活..."
            />
            <IonNote slot="helper">
              可选
            </IonNote>
          </IonItem>

          <IonItem>
            <IonInput
              v-model="form.tags"
              label="标签"
              label-placement="stacked"
              placeholder="用逗号分隔，如：vue, 开源, 前端"
            />
            <IonNote slot="helper">
              可选，用逗号分隔多个标签
            </IonNote>
          </IonItem>
        </IonList>

        <!-- 可见性 -->
        <IonList inset>
          <IonItem>
            <IonToggle v-model="form.isPublic">
              <IonLabel>
                <h3>公开应用</h3>
                <p class="text-xs opacity-60">
                  公开后其他用户可查看此应用
                </p>
              </IonLabel>
            </IonToggle>
          </IonItem>
        </IonList>

        <!-- 提交按钮 -->
        <div class="px-4 pt-4">
          <IonButton
            expand="block"
            :disabled="saving || !form.name.trim()"
            @click="handleSubmit"
          >
            {{ saving ? '创建中...' : '创建应用' }}
          </IonButton>
        </div>
      </form>
    </IonContent>
  </IonPage>
</template>
