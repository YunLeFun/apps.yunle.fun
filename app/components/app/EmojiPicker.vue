<script setup lang="ts">
import { IonIcon, IonInput, IonItem, IonList } from '@ionic/vue'
import { createOutline } from 'ionicons/icons'

const emoji = defineModel<string>({ required: true })

const EMOJI_PRESETS = ['📱', '🚀', '🎮', '🎨', '🔧', '💡', '📝', '🎵', '🌐', '📊', '🛒', '💬', '📷', '🎯', '⚡', '🔥', '🌈', '🧪', '🤖', '📦', '🏠', '🎉', '🧩', '🔔', '🛠️', '📐', '🧮', '🎬', '🌍', '💼']

/** 是否在自定义输入模式 */
const customMode = ref(false)
const customInput = ref('')

/** 校验是否为单个 emoji 字符 */
const EMOJI_REGEX = /^[\p{Emoji_Presentation}\p{Extended_Pictographic}](?:\u{FE0F}|\u{200D}[\p{Emoji_Presentation}\p{Extended_Pictographic}])*$/u

const isCustomValid = computed(() => {
  if (!customInput.value)
    return true

  return EMOJI_REGEX.test(customInput.value)
})

/** 是否为预设中已有的 emoji */
const isPreset = computed(() => EMOJI_PRESETS.includes(emoji.value))

function selectPreset(e: string) {
  emoji.value = e
  customMode.value = false
  customInput.value = ''
}

function enterCustomMode() {
  customMode.value = true
  customInput.value = emoji.value && !isPreset.value ? emoji.value : ''
}

function applyCustomEmoji() {
  if (customInput.value && isCustomValid.value) {
    // 取第一个 emoji 字符（segmenter）
    const segments = [...new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(customInput.value)]
    const firstSegment = segments[0]
    if (firstSegment) {
      emoji.value = firstSegment.segment
      customMode.value = false
    }
  }
}

function onCustomInput(e: Event) {
  const input = (e.target as HTMLInputElement).value
  // 使用 Intl.Segmenter 确保只保留一个 grapheme cluster
  const segments = [...new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(input)]
  const lastSegment = segments[segments.length - 1]
  if (segments.length > 1 && lastSegment) {
    customInput.value = lastSegment.segment
  }
  else {
    customInput.value = input
  }
  if (customInput.value && EMOJI_REGEX.test(customInput.value)) {
    emoji.value = customInput.value
  }
}
</script>

<template>
  <div class="section-header">
    Emoji 图标
  </div>
  <div class="picker-section">
    <div class="emoji-grid">
      <button
        v-for="e in EMOJI_PRESETS"
        :key="e"
        type="button"
        class="emoji-btn"
        :class="{ 'emoji-btn--active': emoji === e && !customMode }"
        @click="selectPreset(e)"
      >
        {{ e }}
      </button>
      <!-- 自定义按钮 -->
      <button
        type="button"
        class="emoji-btn emoji-btn--custom"
        :class="{ 'emoji-btn--active': customMode || (!isPreset && emoji) }"
        @click="enterCustomMode"
      >
        <span v-if="!isPreset && emoji && !customMode" class="text-lg">{{ emoji }}</span>
        <IonIcon v-else :icon="createOutline" class="text-lg opacity-40" />
      </button>
    </div>
  </div>

  <!-- 自定义输入 -->
  <Transition name="slide">
    <IonList v-if="customMode" inset>
      <IonItem :class="{ 'ion-invalid': !isCustomValid }">
        <IonInput
          :model-value="customInput"
          label="自定义 Emoji"
          label-placement="stacked"
          placeholder="粘贴或输入一个 emoji..."
          class="text-xl"
          inputmode="text"
          enterkeyhint="done"
          @ion-input="(e: CustomEvent) => onCustomInput(e as unknown as Event)"
          @keydown.enter="applyCustomEmoji"
        />
        <button
          v-if="customInput && isCustomValid"
          slot="end"
          type="button"
          class="confirm-btn"
          @click="applyCustomEmoji"
        >
          确认
        </button>
      </IonItem>
    </IonList>
  </Transition>
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

.picker-section {
  margin: 0 16px;
  padding: 12px 16px;
  background: var(--ion-item-background, var(--ion-background-color, #fff));
  border-radius: 12px;
  margin-bottom: 8px;
}

.emoji-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, 44px);
  gap: 8px;
  justify-content: center;
  padding: 6px;
}

.emoji-btn {
  width: 44px;
  height: 44px;
  border-radius: 12px;
  font-size: 22px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(142, 142, 147, 0.08);
  border: none;
  transition: all 0.2s ease;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  box-shadow: none;
}

.emoji-btn:active {
  transform: scale(0.92);
}

.emoji-btn--active {
  background: rgba(0, 122, 255, 0.12);
  box-shadow: 0 0 0 2.5px var(--ion-color-primary);
}

.emoji-btn--custom {
  border: 1.5px dashed rgba(142, 142, 147, 0.3);
  background: transparent;
}

.emoji-btn--custom.emoji-btn--active {
  border-style: solid;
  border-color: var(--ion-color-primary);
}

.confirm-btn {
  padding: 4px 12px;
  border-radius: 14px;
  border: none;
  background: var(--ion-color-primary);
  color: white;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.confirm-btn:active {
  opacity: 0.8;
}

.dark .emoji-btn {
  background: rgba(118, 118, 128, 0.16);
}

.dark .emoji-btn--active {
  background: rgba(10, 132, 255, 0.2);
}

.dark .emoji-btn--custom {
  border-color: rgba(118, 118, 128, 0.3);
  background: transparent;
}

/* 展开动画 */
.slide-enter-active,
.slide-leave-active {
  transition: all 0.25s ease;
  overflow: hidden;
}

.slide-enter-from,
.slide-leave-to {
  opacity: 0;
  max-height: 0;
  transform: translateY(-8px);
}

.slide-enter-to,
.slide-leave-from {
  opacity: 1;
  max-height: 100px;
  transform: translateY(0);
}
</style>
