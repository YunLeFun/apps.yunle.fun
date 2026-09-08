<script setup lang="ts">
const props = defineProps<{
  open: boolean
  authLoading: boolean
  currentEmail: string
  isEmailBound: boolean
  presentingElement?: HTMLElement
}>()

const emit = defineEmits<{
  'update:open': [value: boolean]
  'saved': []
}>()

const { changeEmail, verifyEmailBindOtp } = useCloudbaseAuth()
const toast = useToast()

const emailForm = reactive({
  newEmail: '',
  verifyCode: '',
})
const emailVerifyFn = ref<((params: { email: string, token: string }) => Promise<unknown>) | null>(null)
const emailStep = ref<'input' | 'verify'>('input')

watch(() => props.open, (val) => {
  if (val) {
    emailForm.newEmail = ''
    emailForm.verifyCode = ''
    emailVerifyFn.value = null
    emailStep.value = 'input'
  }
})

function dismiss() {
  emit('update:open', false)
}

async function submitEmailChange() {
  if (!emailForm.newEmail.trim()) {
    toast.showWarning('请输入邮箱地址')
    return
  }
  const result = await changeEmail(emailForm.newEmail.trim())
  if (!result)
    return
  if (result.needVerify && result.verifyOtp) {
    emailVerifyFn.value = result.verifyOtp as any
    emailStep.value = 'verify'
  }
  else {
    dismiss()
    emit('saved')
  }
}

async function submitEmailVerify() {
  if (!emailForm.verifyCode.trim()) {
    toast.showWarning('请输入验证码')
    return
  }
  if (!emailVerifyFn.value)
    return
  const ok = await verifyEmailBindOtp(emailVerifyFn.value, emailForm.newEmail, emailForm.verifyCode.trim())
  if (ok) {
    dismiss()
    emit('saved')
  }
}

function handleSubmit() {
  if (emailStep.value === 'input')
    submitEmailChange()
  else
    submitEmailVerify()
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
        <IonTitle>{{ isEmailBound ? '换绑邮箱' : '绑定邮箱' }}</IonTitle>
        <IonButtons slot="end">
          <IonButton :strong="true" :disabled="authLoading" :aria-busy="authLoading" @click="handleSubmit">
            {{ authLoading ? '处理中…' : emailStep === 'input' ? '发送验证' : '确认' }}
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>
    <IonContent>
      <IonList :inset="true" class="mt-4">
        <template v-if="emailStep === 'input'">
          <IonItem v-if="currentEmail">
            <IonInput
              :value="currentEmail"
              label="当前邮箱"
              label-placement="stacked"
              :readonly="true"
            />
          </IonItem>
          <IonItem>
            <IonInput
              v-model="emailForm.newEmail"
              label="新邮箱"
              label-placement="stacked"
              type="email"
              placeholder="请输入新邮箱地址"
              :clear-input="true"
              inputmode="email"
            />
          </IonItem>
        </template>
        <template v-else>
          <IonItem>
            <IonInput
              :value="emailForm.newEmail"
              label="新邮箱"
              label-placement="stacked"
              :readonly="true"
            />
          </IonItem>
          <IonItem>
            <IonInput
              v-model="emailForm.verifyCode"
              label="验证码"
              label-placement="stacked"
              placeholder="请输入邮箱验证码"
              inputmode="numeric"
              :maxlength="6"
              :clear-input="true"
            />
          </IonItem>
        </template>
      </IonList>
      <div v-if="emailStep === 'verify'" class="mt-2 px-6">
        <p class="text-xs ios-secondary-text">
          验证码已发送至 {{ emailForm.newEmail }}，请查收邮件。
        </p>
      </div>
    </IonContent>
  </IonModal>
</template>
