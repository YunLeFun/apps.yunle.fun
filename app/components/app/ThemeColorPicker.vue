<script setup lang="ts">
import { IonIcon, IonInput, IonItem, IonList } from '@ionic/vue'
import { addOutline } from 'ionicons/icons'
import { THEME_COLORS } from '~/types/app'

const themeColor = defineModel<string>({ required: true })

const colorPickerRef = ref<HTMLInputElement>()

function openColorPicker() {
  colorPickerRef.value?.click()
}

function onColorPickerChange(e: Event) {
  const input = e.target as HTMLInputElement
  themeColor.value = input.value.toUpperCase()
}
</script>

<template>
  <div class="section-header">
    主题色
  </div>
  <div class="picker-section">
    <div class="color-grid">
      <button
        v-for="c in THEME_COLORS"
        :key="c"
        type="button"
        class="color-swatch"
        :class="{ 'color-swatch--active': themeColor === c }"
        :style="{ backgroundColor: c }"
        @click="themeColor = c"
      >
        <span v-if="themeColor === c" class="color-check">✓</span>
      </button>
      <button
        type="button"
        class="color-swatch color-swatch--custom"
        :style="!THEME_COLORS.includes(themeColor as any) ? { backgroundColor: themeColor } : {}"
        :class="{ 'color-swatch--active': !THEME_COLORS.includes(themeColor as any) }"
        @click="openColorPicker"
      >
        <span v-if="!THEME_COLORS.includes(themeColor as any)" class="color-check">✓</span>
        <span v-else class="color-plus"><IonIcon :icon="addOutline" /></span>
      </button>
    </div>
    <input
      ref="colorPickerRef"
      type="color"
      :value="themeColor"
      class="sr-only"
      @input="onColorPickerChange"
    >
  </div>
  <IonList inset>
    <IonItem>
      <IonInput
        v-model="themeColor"
        label="色值"
        label-placement="stacked"
        placeholder="#007AFF"
        :maxlength="7"
        class="font-mono"
      />
      <div slot="end" class="color-indicator" :style="{ backgroundColor: themeColor }" />
    </IonItem>
  </IonList>
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

.color-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  justify-content: center;
  padding: 6px;
}

.color-swatch {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  border: none;
  cursor: pointer;
  position: relative;
  transition: all 0.2s ease;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.1);
  -webkit-tap-highlight-color: transparent;
}

.color-swatch:active {
  transform: scale(0.9);
}

.color-swatch--active {
  box-shadow:
    0 0 0 3px var(--ion-background-color, #fff),
    0 0 0 5.5px var(--ion-text-color);
}

.color-swatch--custom {
  background: conic-gradient(#ff3b30, #ff9500, #ffd60a, #34c759, #00c7be, #007aff, #5856d6, #af52de, #ff2d55, #ff3b30);
}

.color-swatch--custom.color-swatch--active {
  background: var(
    --custom-bg,
    conic-gradient(#ff3b30, #ff9500, #ffd60a, #34c759, #00c7be, #007aff, #5856d6, #af52de, #ff2d55, #ff3b30)
  );
}

.color-check {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: white;
  font-size: 16px;
  font-weight: 700;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.3);
}

.color-plus {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: white;
  font-size: 20px;
  font-weight: 300;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.3);
}

.color-indicator {
  width: 24px;
  height: 24px;
  border-radius: 50%;
  box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.1);
  flex-shrink: 0;
}
</style>
