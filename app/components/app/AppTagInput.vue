<script setup lang="ts">
import { IonIcon } from '@ionic/vue'
import { closeCircle } from 'ionicons/icons'

const tags = defineModel<string[]>({ required: true })

const inputValue = ref('')
const inputRef = ref<HTMLInputElement>()

function addTag() {
  const value = inputValue.value.trim()

  if (!value)
    return

  if (tags.value.includes(value)) {
    inputValue.value = ''

    return
  }

  if (tags.value.length >= 10)
    return

  tags.value = [...tags.value, value]
  inputValue.value = ''
}

function removeTag(index: number) {
  tags.value = tags.value.filter((_, i) => i !== index)
}

function onKeydown(e: KeyboardEvent) {
  if (e.key === 'Enter' || e.key === ',' || e.key === '，') {
    e.preventDefault()
    addTag()
  }
  if (e.key === 'Backspace' && !inputValue.value && tags.value.length > 0) {
    removeTag(tags.value.length - 1)
  }
}

function focusInput() {
  inputRef.value?.focus()
}
</script>

<template>
  <div class="section-header">
    标签
  </div>
  <div class="tag-input-container" @click="focusInput">
    <TransitionGroup name="tag" tag="div" class="tag-list">
      <span
        v-for="(tag, index) in tags"
        :key="tag"
        class="tag-chip"
      >
        <span class="tag-text">{{ tag }}</span>
        <button type="button" class="tag-remove" @click.stop="removeTag(index)">
          <IonIcon :icon="closeCircle" class="tag-remove-icon" />
        </button>
      </span>
      <input
        key="input"
        ref="inputRef"
        v-model="inputValue"
        type="text"
        class="tag-input"
        placeholder="输入后回车添加..."
        :disabled="tags.length >= 10"
        enterkeyhint="done"
        @keydown="onKeydown"
        @blur="addTag"
      >
    </TransitionGroup>
    <p class="tag-hint">
      {{ tags.length }}/10，回车或逗号添加
    </p>
  </div>
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

.tag-input-container {
  margin: 0 16px;
  padding: 12px;
  background: var(--ion-item-background, var(--ion-background-color, #fff));
  border-radius: 12px;
  margin-bottom: 8px;
  cursor: text;
}

.tag-list {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  align-items: center;
}

.tag-chip {
  display: inline-flex;
  align-items: center;
  gap: 2px;
  padding: 4px 6px 4px 10px;
  border-radius: 16px;
  background: rgba(0, 122, 255, 0.1);
  color: var(--ion-color-primary);
  font-size: 13px;
  font-weight: 500;
  line-height: 1.4;
  max-width: 160px;
}

.tag-text {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.tag-remove {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 20px;
  height: 20px;
  padding: 0;
  border: none;
  background: transparent;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  flex-shrink: 0;
}

.tag-remove-icon {
  font-size: 16px;
  color: var(--ion-color-primary);
  opacity: 0.6;
}

.tag-remove:active .tag-remove-icon {
  opacity: 1;
}

.tag-input {
  flex: 1;
  min-width: 100px;
  padding: 4px 2px;
  border: none;
  outline: none;
  background: transparent;
  font-size: 14px;
  color: var(--ion-text-color);
  line-height: 1.4;
}

.tag-input::placeholder {
  color: var(--ion-color-medium);
  opacity: 0.6;
}

.tag-input:disabled {
  opacity: 0.4;
}

.tag-hint {
  margin-top: 8px;
  font-size: 12px;
  color: var(--ion-color-medium);
  opacity: 0.7;
}

/* 标签动画 */
.tag-enter-active {
  transition: all 0.2s ease;
}

.tag-leave-active {
  transition: all 0.15s ease;
}

.tag-enter-from {
  opacity: 0;
  transform: scale(0.8);
}

.tag-leave-to {
  opacity: 0;
  transform: scale(0.8);
}

.dark .tag-chip {
  background: rgba(10, 132, 255, 0.15);
}
</style>
