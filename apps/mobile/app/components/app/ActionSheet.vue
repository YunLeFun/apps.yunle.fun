<script setup lang="ts">
import type { ActionSheetButton } from '@ionic/vue'

defineProps<{
  isOpen: boolean
}>()

const emit = defineEmits(['didDismiss'])

const actionSheetButtons = ref<ActionSheetButton[]>([
  {
    text: 'Delete',
    role: 'destructive',
    data: {
      action: 'delete',
    },
  },
  {
    text: 'Share',
    data: {
      action: 'share',
    },
  },
  {
    text: 'Cancel',
    role: 'cancel',
    data: {
      action: 'cancel',
    },
  },
])
</script>

<template>
  <ion-action-sheet
    :is-open="isOpen"
    header="Actions"
    :buttons="actionSheetButtons"
    @did-dismiss="emit('didDismiss')"
  />
</template>
