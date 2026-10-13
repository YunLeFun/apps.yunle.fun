<script setup lang="ts">
import type { AppIconAssetRole } from '~/types/app'
import type { AppIconAssetsDraft } from '~/utils/appIconAssets'
import { IonInput, IonItem, IonList, IonNote, IonSpinner } from '@ionic/vue'
import { normalizeAppIconFile } from '~/utils/appIconFile'
import { getRequestErrorInfo } from '~/utils/requestError'

type VariantKey = 'src' | 'darkSrc'
type UploadKey = `${AppIconAssetRole}:${VariantKey}`

const iconAssets = defineModel<AppIconAssetsDraft>('iconAssets', { required: true })
const legacyLogo = defineModel<string>('legacyLogo', { default: '' })
const busy = defineModel<boolean>('busy', { default: false })

const { $api } = useNuxtApp()
const toast = useToast()
const uploading = reactive<Partial<Record<UploadKey, boolean>>>({})

watchEffect(() => {
  busy.value = Object.values(uploading).some(Boolean)
})

async function onFileSelected(event: Event, role: AppIconAssetRole, variant: VariantKey) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  input.value = ''
  if (!file)
    return

  const key: UploadKey = `${role}:${variant}`
  try {
    uploading[key] = true
    const normalized = await normalizeAppIconFile(file, role)
    const body = new FormData()
    body.append('assetRole', role)
    body.append('file', normalized)
    const result = await $api<{ fileID: string }>('/api/apps/icon-assets', {
      method: 'POST',
      body,
    })
    iconAssets.value[role === 'app-icon' ? 'appIcon' : 'mark'][variant] = result.fileID
    toast.showSuccess(variant === 'darkSrc' ? '深色图标已上传' : '图标已上传')
  }
  catch (error) {
    const errorInfo = getRequestErrorInfo(error, '图标上传失败，请稍后重试')
    toast.showError(errorInfo.message, errorInfo.copyText)
  }
  finally {
    uploading[key] = false
  }
}
</script>

<template>
  <section class="icon-assets-editor">
    <div class="section-heading">
      <div>
        <h2>应用图标</h2>
        <p>完整图标建议提供；主体图标与深色版本按需补充。</p>
      </div>
    </div>

    <IonList inset>
      <div class="asset-block">
        <div class="asset-title-row">
          <div>
            <strong>完整图标</strong>
            <span class="recommended">推荐</span>
            <p>自带背景，保留满画布，不要预先裁圆角或添加阴影。</p>
          </div>
          <label class="upload-action">
            <IonSpinner v-if="uploading['app-icon:src']" name="crescent" />
            <span v-else>上传</span>
            <input
              type="file"
              accept="image/png,image/webp,image/svg+xml"
              :disabled="uploading['app-icon:src']"
              @change="onFileSelected($event, 'app-icon', 'src')"
            >
          </label>
        </div>
        <IonItem lines="none">
          <IonInput
            v-model="iconAssets.appIcon.src"
            label="或输入图片 URL"
            label-placement="stacked"
            placeholder="https://example.com/app-icon.png"
            type="url"
          />
        </IonItem>
      </div>

      <div class="asset-divider" />

      <div class="asset-block">
        <div class="asset-title-row">
          <div>
            <strong>主体图标</strong>
            <span class="optional">可选</span>
            <p>透明背景；上传后会自动居中到约 80% 安全区，适配玻璃、渐变等风格。</p>
          </div>
          <label class="upload-action">
            <IonSpinner v-if="uploading['mark:src']" name="crescent" />
            <span v-else>上传</span>
            <input
              type="file"
              accept="image/png,image/webp,image/svg+xml"
              :disabled="uploading['mark:src']"
              @change="onFileSelected($event, 'mark', 'src')"
            >
          </label>
        </div>
        <IonItem lines="none">
          <IonInput
            v-model="iconAssets.mark.src"
            label="或输入图片 URL"
            label-placement="stacked"
            placeholder="https://example.com/mark.png"
            type="url"
          />
        </IonItem>
      </div>
    </IonList>

    <details class="dark-assets">
      <summary>深色模式专用图标（可选）</summary>
      <p class="dark-help">
        未提供时自动沿用默认图标；平台不会强制反色。
      </p>
      <IonList inset>
        <IonItem>
          <IonInput
            v-model="iconAssets.appIcon.darkSrc"
            label="完整图标 · 深色"
            label-placement="stacked"
            placeholder="https://example.com/app-icon-dark.png"
            type="url"
          />
          <label slot="end" class="upload-action compact">
            <IonSpinner v-if="uploading['app-icon:darkSrc']" name="crescent" />
            <span v-else>上传</span>
            <input
              type="file"
              accept="image/png,image/webp,image/svg+xml"
              :disabled="uploading['app-icon:darkSrc']"
              @change="onFileSelected($event, 'app-icon', 'darkSrc')"
            >
          </label>
        </IonItem>
        <IonItem>
          <IonInput
            v-model="iconAssets.mark.darkSrc"
            label="主体图标 · 深色"
            label-placement="stacked"
            placeholder="https://example.com/mark-dark.png"
            type="url"
          />
          <label slot="end" class="upload-action compact">
            <IonSpinner v-if="uploading['mark:darkSrc']" name="crescent" />
            <span v-else>上传</span>
            <input
              type="file"
              accept="image/png,image/webp,image/svg+xml"
              :disabled="uploading['mark:darkSrc']"
              @change="onFileSelected($event, 'mark', 'darkSrc')"
            >
          </label>
        </IonItem>
      </IonList>
    </details>

    <IonNote v-if="legacyLogo" class="legacy-note">
      当前应用仍保留旧版 Logo 作为兼容回退。
      <button type="button" @click="legacyLogo = ''">
        清除旧版 Logo
      </button>
    </IonNote>
  </section>
</template>

<style scoped>
.icon-assets-editor {
  margin-top: 8px;
}

.section-heading {
  padding: 18px 20px 2px;
}

.section-heading h2 {
  margin: 0;
  font-size: 15px;
  font-weight: 600;
}

.section-heading p,
.asset-title-row p,
.dark-help {
  margin: 4px 0 0;
  color: var(--ion-color-medium);
  font-size: 12px;
  line-height: 1.45;
}

.asset-block {
  padding: 14px 16px 6px;
}

.asset-title-row {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}

.asset-title-row strong {
  font-size: 15px;
}

.recommended,
.optional {
  margin-left: 7px;
  padding: 2px 6px;
  border-radius: 999px;
  font-size: 10px;
  font-weight: 600;
}

.recommended {
  color: var(--ion-color-primary);
  background: color-mix(in srgb, var(--ion-color-primary) 12%, transparent);
}

.optional {
  color: var(--ion-color-medium);
  background: var(--ylf-fill-secondary);
}

.asset-divider {
  height: 1px;
  margin-left: 16px;
  background: var(--ylf-separator, rgba(60, 60, 67, 0.18));
}

.upload-action {
  display: inline-flex;
  flex: 0 0 auto;
  align-items: center;
  justify-content: center;
  min-width: 58px;
  min-height: 34px;
  border-radius: 999px;
  color: var(--ion-color-primary);
  background: color-mix(in srgb, var(--ion-color-primary) 10%, transparent);
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
}

.upload-action.compact {
  min-width: 48px;
  margin-top: 12px;
}

.upload-action input {
  position: absolute;
  width: 1px;
  height: 1px;
  opacity: 0;
  pointer-events: none;
}

.upload-action ion-spinner {
  width: 18px;
  height: 18px;
}

.dark-assets {
  margin: 12px 16px 0;
  padding: 13px 4px 4px;
  border-top: 1px solid var(--ylf-separator, rgba(60, 60, 67, 0.18));
}

.dark-assets summary {
  padding: 0 4px;
  color: var(--ion-color-primary);
  font-size: 14px;
  cursor: pointer;
}

.dark-help {
  padding: 0 4px 4px;
}

.legacy-note {
  display: block;
  padding: 10px 20px 0;
  line-height: 1.5;
}

.legacy-note button {
  border: 0;
  padding: 0;
  color: var(--ion-color-danger);
  background: transparent;
}
</style>
