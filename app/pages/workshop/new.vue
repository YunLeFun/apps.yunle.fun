<script setup lang="ts">
import {
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonInput,
  IonItem,
  IonList,
  IonNote,
  IonPage,
  IonSelect,
  IonSelectOption,
  IonSpinner,
  IonTextarea,
  IonTitle,
  IonToolbar,
} from '@ionic/vue'
import { checkmark, chevronBack } from 'ionicons/icons'

const router = useRouter()
const {
  form,
  saving,
  iconUploadBusy,
  slugError,
  slugChecking,
  nameError,
  nameChecking,
  nameAvailable,
  SLUG_REGEX,
  onSlugInput,
  handleSubmit,
} = useAppForm('create')
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonButton @click="router.back()">
            <IonIcon slot="start" :icon="chevronBack" />
            返回
          </IonButton>
        </IonButtons>
        <IonTitle>创建应用</IonTitle>
        <IonButtons slot="end">
          <IonButton :disabled="saving || iconUploadBusy || !form.name.trim() || !!nameError || nameChecking || !!slugError" @click="handleSubmit">
            <IonIcon v-if="!saving" slot="icon-only" :icon="checkmark" />
            <IonSpinner v-else name="crescent" />
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true" class="ion-padding">
      <form @submit.prevent="handleSubmit">
        <!-- 图标预览 -->
        <AppIconPreview :emoji="form.emoji" :theme-color="form.themeColor" :logo="form.logo" :icon-assets="form.iconAssets" />

        <!-- 基本信息 -->
        <IonList inset>
          <IonItem :class="{ 'ion-invalid': nameError, 'ion-valid': nameAvailable }">
            <IonInput
              v-model="form.name"
              label="名称"
              label-placement="stacked"
              placeholder="输入应用名称"
              :maxlength="50"
              required
            />
            <IonSpinner v-if="nameChecking" slot="end" name="crescent" class="slug-spinner" />
          </IonItem>
          <IonNote
            class="name-availability-note"
            :color="nameError ? 'danger' : nameAvailable ? 'success' : 'medium'"
            aria-live="polite"
          >
            {{ nameChecking ? '正在检查名称…' : nameError || (nameAvailable ? '名称可用' : '显示名称可重复，上架市场时另选唯一短名') }}
          </IonNote>

          <IonItem :class="{ 'ion-invalid': slugError, 'ion-valid': !slugError && !slugChecking && form.slug && SLUG_REGEX.test(form.slug) }">
            <IonInput
              v-model="form.slug"
              label="标识符 (slug)"
              label-placement="stacked"
              placeholder="my-app"
              :maxlength="50"
              class="font-mono"
              @ion-input="onSlugInput"
            />
            <IonSpinner v-if="slugChecking" slot="end" name="crescent" class="slug-spinner" />
            <IonNote v-if="slugError" slot="error">
              {{ slugError }}
            </IonNote>
            <IonNote v-else slot="helper">
              在你的命名空间内唯一，用于个人应用地址
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

        <!-- Emoji 选择 -->
        <AppEmojiPicker v-model="form.emoji" />

        <!-- 主题色选择 -->
        <AppThemeColorPicker v-model="form.themeColor" />

        <AppIconAssetsEditor v-model:icon-assets="form.iconAssets" v-model:legacy-logo="form.logo" v-model:busy="iconUploadBusy" />

        <!-- 链接信息 -->
        <div class="section-header">
          链接
        </div>
        <IonList inset>
          <IonItem>
            <IonInput
              v-model="form.websiteUrl"
              label="网址（必填）"
              label-placement="stacked"
              placeholder="https://example.com"
              type="url"
            />
          </IonItem>

          <IonItem>
            <IonInput
              v-model="form.privacyPolicyUrl"
              label="隐私政策（必填）"
              label-placement="stacked"
              placeholder="https://example.yunle.fun/privacy"
              type="url"
            />
          </IonItem>

          <IonItem>
            <IonInput
              v-model="form.supportUrl"
              label="支持链接（必填）"
              label-placement="stacked"
              placeholder="https://support.yunle.fun"
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

        <!-- 分类 -->
        <AppCategoryPicker v-model="form.category" />

        <!-- 标签 -->
        <AppTagInput v-model="form.tags" />

        <!-- 分发属性 -->
        <IonList inset class="mt-4">
          <IonItem>
            <IonSelect v-model="form.audience" label="可见范围" label-placement="stacked">
              <IonSelectOption value="public">
                公开
              </IonSelectOption>
              <IonSelectOption value="workshop">
                坊客专属
              </IonSelectOption>
              <IonSelectOption value="owner">
                仅自己
              </IonSelectOption>
            </IonSelect>
            <IonNote slot="helper">
              {{ form.audience === 'workshop' ? '仅在个人工坊展示，站点访问权限由开发者决定' : form.audience === 'owner' ? '仅你本人可以在创作管理中看到' : '发布后展示在个人主页，可另行投稿云乐坊' }}
            </IonNote>
          </IonItem>
          <IonItem>
            <IonSelect v-model="form.accessMode" label="访问方式" label-placement="stacked">
              <IonSelectOption value="public">
                直接访问
              </IonSelectOption>
              <IonSelectOption value="login_required">
                登录后使用
              </IonSelectOption>
              <IonSelectOption value="invite_only">
                仅限受邀用户
              </IonSelectOption>
            </IonSelect>
          </IonItem>
          <IonItem>
            <IonSelect v-model="form.releaseStage" label="发布阶段" label-placement="stacked">
              <IonSelectOption value="stable">
                Stable
              </IonSelectOption>
              <IonSelectOption value="beta">
                Beta
              </IonSelectOption>
            </IonSelect>
            <IonNote slot="helper">
              保存后立即形成不可变版本；投稿云乐坊时再进入人工审核
            </IonNote>
          </IonItem>
        </IonList>

        <!-- 提交按钮 -->
        <div class="px-4 pb-8 pt-4">
          <IonButton
            expand="block"
            :disabled="saving || iconUploadBusy || !form.name.trim() || !!nameError || nameChecking || !!slugError || slugChecking"
            class="submit-btn"
            @click="handleSubmit"
          >
            <IonSpinner v-if="saving" name="crescent" class="mr-2" />
            {{ saving ? '创建中...' : '创建应用' }}
          </IonButton>
        </div>
      </form>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.section-header {
  padding: 24px 20px 6px;
  font-size: 13px;
  font-weight: 400;
  color: var(--ion-color-medium);
  text-transform: uppercase;
  letter-spacing: 0.02em;
}

.slug-spinner {
  width: 16px;
  height: 16px;
  color: var(--ion-color-medium);
}

.name-availability-note {
  display: block;
  min-height: 18px;
  margin: 4px 16px 8px;
  font-size: 12px;
}

.submit-btn {
  --border-radius: 14px;
  font-weight: 600;
  font-size: 17px;
  height: 50px;
}
</style>
