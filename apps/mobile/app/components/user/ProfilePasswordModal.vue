<script setup lang="ts">
import { lockClosedOutline } from 'ionicons/icons'

const props = defineProps<{
  open: boolean
  authLoading: boolean
  presentingElement?: HTMLElement
}>()

const emit = defineEmits<{
  'update:open': [value: boolean]
  'saved': []
}>()

const { resetPasswordWithOld } = useCloudbaseAuth()
const toast = useToast()

const passwordForm = reactive({
  oldPassword: '',
  newPassword: '',
  confirmPassword: '',
})

watch(() => props.open, (val) => {
  if (val) {
    passwordForm.oldPassword = ''
    passwordForm.newPassword = ''
    passwordForm.confirmPassword = ''
  }
})

function dismiss() {
  emit('update:open', false)
}

async function submitPasswordChange() {
  if (!passwordForm.oldPassword) {
    toast.showWarning('请输入当前密码')
    return
  }
  if (!passwordForm.newPassword || passwordForm.newPassword.length < 8) {
    toast.showWarning('新密码至少 8 位')
    return
  }
  if (passwordForm.newPassword !== passwordForm.confirmPassword) {
    toast.showWarning('两次密码不一致')
    return
  }
  const ok = await resetPasswordWithOld(passwordForm.oldPassword, passwordForm.newPassword)
  if (ok) {
    dismiss()
    emit('saved')
  }
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
        <IonTitle>重设密码</IonTitle>
        <IonButtons slot="end">
          <IonButton :strong="true" :disabled="authLoading" @click="submitPasswordChange">
            完成
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>
    <IonContent>
      <IonList :inset="true" class="mt-4">
        <IonItem>
          <IonInput
            v-model="passwordForm.oldPassword"
            label="当前密码"
            label-placement="stacked"
            type="password"
            placeholder="请输入当前密码"
            :clear-input="true"
          />
        </IonItem>
        <IonItem>
          <IonInput
            v-model="passwordForm.newPassword"
            label="新密码"
            label-placement="stacked"
            type="password"
            placeholder="至少 8 位"
            :clear-input="true"
          />
        </IonItem>
        <IonItem>
          <IonInput
            v-model="passwordForm.confirmPassword"
            label="确认新密码"
            label-placement="stacked"
            type="password"
            placeholder="请再次输入新密码"
            :clear-input="true"
          />
        </IonItem>
      </IonList>
      <div class="mt-2 px-6">
        <p class="text-xs ios-secondary-text flex items-center gap-1">
          <IonIcon :icon="lockClosedOutline" class="text-xs" />
          密码修改后，所有设备需重新登录。
        </p>
      </div>
    </IonContent>
  </IonModal>
</template>
