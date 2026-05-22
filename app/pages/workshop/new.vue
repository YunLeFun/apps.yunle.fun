<script setup lang="ts">
import {
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
  IonSpinner,
  IonTextarea,
  IonTitle,
  IonToggle,
  IonToolbar,
} from '@ionic/vue'
import { checkmark, chevronBack } from 'ionicons/icons'

const router = useRouter()
const {
  form,
  saving,
  slugError,
  slugChecking,
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
          <IonButton :disabled="saving || !form.name.trim() || !!slugError" @click="handleSubmit">
            <IonIcon v-if="!saving" slot="icon-only" :icon="checkmark" />
            <IonSpinner v-else name="crescent" />
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true" class="ion-padding">
      <form @submit.prevent="handleSubmit">
        <!-- 图标预览 -->
        <AppIconPreview :emoji="form.emoji" :theme-color="form.themeColor" :logo="form.logo" />

        <!-- 基本信息 -->
        <IonList inset>
          <IonItem>
            <IonInput
              v-model="form.name"
              label="名称"
              label-placement="stacked"
              placeholder="输入应用名称"
              :maxlength="50"
              required
            />
          </IonItem>

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
              唯一标识，用于 URL 路径
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

        <!-- Logo -->
        <div class="section-header">
          Logo（可选）
        </div>
        <IonList inset>
          <IonItem>
            <IonInput
              v-model="form.logo"
              label="图片 URL"
              label-placement="stacked"
              placeholder="https://example.com/logo.png"
              type="url"
            />
            <IonNote slot="helper">
              设置后优先展示 Logo，替代 Emoji
            </IonNote>
          </IonItem>
        </IonList>

        <!-- 链接信息 -->
        <div class="section-header">
          链接
        </div>
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

        <!-- 分类 -->
        <AppCategoryPicker v-model="form.category" />

        <!-- 标签 -->
        <AppTagInput v-model="form.tags" />

        <!-- 可见性 -->
        <IonList inset class="mt-4">
          <IonItem>
            <IonToggle v-model="form.isPublic">
              <IonLabel>
                <h3>公开应用</h3>
                <p class="text-xs" style="color: var(--ion-color-medium)">
                  提交后将进入审核队列，通过后才会在工坊/寻乐对所有人可见
                </p>
              </IonLabel>
            </IonToggle>
          </IonItem>
        </IonList>

        <!-- 提交按钮 -->
        <div class="px-4 pb-8 pt-4">
          <IonButton
            expand="block"
            :disabled="saving || !form.name.trim() || !!slugError || slugChecking"
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

.submit-btn {
  --border-radius: 14px;
  font-weight: 600;
  font-size: 17px;
  height: 50px;
}
</style>
