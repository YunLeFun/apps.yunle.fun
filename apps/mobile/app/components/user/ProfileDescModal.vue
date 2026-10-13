<script setup lang="ts">
const props = defineProps<{
  open: boolean
  authLoading: boolean
  description: string
  presentingElement?: HTMLElement
}>()

const emit = defineEmits<{
  'update:open': [value: boolean]
  'save': [value: string]
}>()

const descEditValue = ref('')

watch(() => props.open, (val) => {
  if (val)
    descEditValue.value = props.description || ''
})

function dismiss() {
  emit('update:open', false)
}

function handleSave() {
  emit('save', descEditValue.value.trim())
}
</script>

<template>
  <IonModal
    :is-open="open"
    :presenting-element="presentingElement"
    :can-dismiss="true"
    @did-dismiss="dismiss"
  >
    <IonHeader>
      <IonToolbar>
        <IonButtons slot="start">
          <IonButton @click="dismiss">
            取消
          </IonButton>
        </IonButtons>
        <IonTitle>编辑简介</IonTitle>
        <IonButtons slot="end">
          <IonButton :strong="true" :disabled="authLoading" @click="handleSave">
            完成
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>
    <IonContent>
      <IonList :inset="true" class="mt-4">
        <IonItem>
          <IonTextarea
            v-model="descEditValue"
            label="个人简介"
            label-placement="stacked"
            placeholder="介绍一下自己吧"
            :maxlength="200"
            :auto-grow="true"
            :rows="3"
            :counter="true"
          />
        </IonItem>
      </IonList>
    </IonContent>
  </IonModal>
</template>
