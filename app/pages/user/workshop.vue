<script setup lang="ts">
import type {
  WorkshopJoinPolicy,
  WorkshopManagementView,
  WorkshopMembership,
} from '~/types/workshop'
import {
  alertController,
  IonBackButton,
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
  IonSelect,
  IonSelectOption,
  IonSpinner,
  IonTextarea,
  IonTitle,
  IonToolbar,
  onIonViewWillEnter,
} from '@ionic/vue'
import {
  banOutline,
  checkmarkOutline,
  closeOutline,
  copyOutline,
  personRemoveOutline,
  powerOutline,
  qrCodeOutline,
  shareOutline,
} from 'ionicons/icons'
import QRCode from 'qrcode'

const workshopModule = usePersonalWorkshop()
const toast = useToast()
const loading = ref(true)
const saving = ref(false)
const management = ref<WorkshopManagementView | null>(null)
const name = ref('')
const description = ref('')
const joinPolicy = ref<WorkshopJoinPolicy>('approval')
const qrcodeDataUrl = ref('')

const workshopUrl = computed(() => {
  const id = management.value?.workshop._id
  if (!id)
    return ''
  const origin = import.meta.client ? window.location.origin : 'https://apps.yunle.fun'
  return `${origin}/w/${id}`
})

async function load() {
  loading.value = true
  try {
    management.value = await workshopModule.getManagement()
    syncForm()
    await renderQrCode()
  }
  catch (reason: unknown) {
    toast.showError(reason instanceof Error ? reason.message : '个人工坊加载失败')
  }
  finally {
    loading.value = false
  }
}

function syncForm() {
  name.value = management.value?.workshop.name || ''
  description.value = management.value?.workshop.description || ''
  joinPolicy.value = management.value?.workshop.joinPolicy || 'approval'
}

async function renderQrCode() {
  qrcodeDataUrl.value = workshopUrl.value
    ? await QRCode.toDataURL(workshopUrl.value, {
        width: 560,
        margin: 2,
        errorCorrectionLevel: 'M',
        color: {
          dark: '#1C1C1E',
          light: '#FFFFFF',
        },
      })
    : ''
}

async function createWorkshop() {
  saving.value = true
  try {
    await workshopModule.create({
      name: name.value.trim() || undefined,
      description: description.value.trim() || undefined,
    })
    toast.showSuccess('个人工坊已创建')
    await load()
  }
  catch (reason: unknown) {
    toast.showError(reason instanceof Error ? reason.message : '创建失败')
  }
  finally {
    saving.value = false
  }
}

async function saveWorkshop() {
  if (!management.value)
    return
  saving.value = true
  try {
    const workshop = await workshopModule.update(management.value.workshop._id, {
      name: name.value.trim(),
      description: description.value.trim(),
      joinPolicy: joinPolicy.value,
    })
    management.value.workshop = workshop
    syncForm()
    toast.showSuccess('个人工坊设置已保存')
  }
  catch (reason: unknown) {
    toast.showError(reason instanceof Error ? reason.message : '保存失败')
  }
  finally {
    saving.value = false
  }
}

async function handleJoinPolicyChange(event: CustomEvent<{ value: WorkshopJoinPolicy }>) {
  const next = event.detail.value
  const previous = management.value?.workshop.joinPolicy || 'approval'
  if (next !== 'open' || previous === 'open')
    return

  const alert = await alertController.create({
    header: '确认开放加入',
    message: '任何获得工坊链接的登录用户都可以直接加入。已加入坊客不受策略切换影响。',
    buttons: [
      {
        text: '取消',
        role: 'cancel',
        handler: () => {
          joinPolicy.value = previous
        },
      },
      { text: '确认开放' },
    ],
  })
  await alert.present()
}

async function toggleStatus() {
  if (!management.value)
    return
  const disabled = management.value.workshop.status === 'disabled'
  const alert = await alertController.create({
    header: disabled ? '恢复个人工坊' : '停用个人工坊',
    message: disabled
      ? '恢复后，原有坊客将重新获得工坊作品访问权限。'
      : '停用后所有坊客将暂时无法查看工坊作品，成员关系和申请记录会保留。',
    buttons: [
      { text: '取消', role: 'cancel' },
      {
        text: disabled ? '恢复' : '停用',
        role: disabled ? undefined : 'destructive',
        handler: async () => {
          const workshop = await workshopModule.update(management.value!.workshop._id, {
            status: disabled ? 'active' : 'disabled',
          })
          management.value!.workshop = workshop
          toast.showSuccess(disabled ? '个人工坊已恢复' : '个人工坊已停用')
        },
      },
    ],
  })
  await alert.present()
}

async function decide(member: WorkshopMembership, action: 'approve' | 'reject' | 'remove' | 'block' | 'unblock') {
  if (!management.value)
    return
  try {
    await workshopModule.decide(
      management.value.workshop._id,
      member.userUid,
      action,
    )
    toast.showSuccess(actionLabel(action))
    await load()
  }
  catch (reason: unknown) {
    toast.showError(reason instanceof Error ? reason.message : '操作失败')
  }
}

async function shareWorkshop() {
  if (!workshopUrl.value)
    return
  if (navigator.share) {
    await navigator.share({
      title: management.value?.workshop.name || '个人工坊',
      text: '打开链接申请加入我的个人工坊',
      url: workshopUrl.value,
    })
    return
  }
  await copyWorkshopUrl()
}

async function copyWorkshopUrl() {
  if (!workshopUrl.value)
    return
  await navigator.clipboard.writeText(workshopUrl.value)
  toast.showSuccess('工坊链接已复制')
}

function actionLabel(action: 'approve' | 'reject' | 'remove' | 'block' | 'unblock') {
  switch (action) {
    case 'approve': return '已同意加入'
    case 'reject': return '已拒绝申请'
    case 'remove': return '已移除坊客'
    case 'block': return '已拉黑'
    case 'unblock': return '已解除拉黑'
  }
}

onIonViewWillEnter(load)
</script>

<template>
  <IonPage>
    <IonHeader :translucent="true">
      <IonToolbar>
        <IonButtons slot="start">
          <IonBackButton default-href="/tabs/me" text="" />
        </IonButtons>
        <IonTitle>我的个人工坊</IonTitle>
        <IonButtons v-if="management" slot="end">
          <IonButton :disabled="saving || !name.trim()" @click="saveWorkshop">
            <IonSpinner v-if="saving" name="crescent" />
            <IonIcon v-else slot="icon-only" :icon="checkmarkOutline" />
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true" class="management-content">
      <div v-if="loading" class="management-loading">
        <IonSpinner name="crescent" />
      </div>

      <div v-else-if="!management" class="create-workshop">
        <div class="create-symbol">
          <IonIcon :icon="qrCodeOutline" />
        </div>
        <span>仅需创建一次</span>
        <h1>创建你的个人工坊</h1>
        <p>发布坊客专属作品，通过固定二维码邀请其他用户申请加入。</p>
        <IonList inset>
          <IonItem>
            <IonInput
              v-model="name"
              label="工坊名称"
              label-placement="stacked"
              placeholder="留空将使用默认名称"
              :maxlength="40"
            />
          </IonItem>
          <IonItem>
            <IonTextarea
              v-model="description"
              label="简介"
              label-placement="stacked"
              :maxlength="200"
              :rows="3"
            />
          </IonItem>
        </IonList>
        <IonButton :disabled="saving" @click="createWorkshop">
          <IonSpinner v-if="saving" name="crescent" />
          创建个人工坊
        </IonButton>
      </div>

      <template v-else>
        <section class="workshop-identity">
          <span>固定工坊号</span>
          <strong>{{ management.workshop._id }}</strong>
          <IonNote>名称可以修改，工坊号和二维码地址保持不变</IonNote>
        </section>

        <IonList inset>
          <IonItem>
            <IonInput v-model="name" label="名称" label-placement="stacked" :maxlength="40" />
          </IonItem>
          <IonItem>
            <IonTextarea
              v-model="description"
              label="简介"
              label-placement="stacked"
              :maxlength="200"
              :rows="3"
            />
          </IonItem>
          <IonItem>
            <IonSelect
              v-model="joinPolicy"
              label="加入方式"
              label-placement="stacked"
              @ion-change="handleJoinPolicyChange"
            >
              <IonSelectOption value="approval">
                申请后审批
              </IonSelectOption>
              <IonSelectOption value="open">
                登录后直接加入
              </IonSelectOption>
              <IonSelectOption value="closed">
                暂停接受加入
              </IonSelectOption>
            </IonSelect>
          </IonItem>
        </IonList>

        <section class="workshop-qr">
          <img v-if="qrcodeDataUrl" :src="qrcodeDataUrl" alt="个人工坊二维码">
          <div>
            <span>扫码申请加入</span>
            <p>{{ workshopUrl }}</p>
            <div class="workshop-qr-actions">
              <IonButton size="small" @click="shareWorkshop">
                <IonIcon slot="start" :icon="shareOutline" />
                分享
              </IonButton>
              <IonButton size="small" fill="outline" @click="copyWorkshopUrl">
                <IonIcon slot="start" :icon="copyOutline" />
                复制链接
              </IonButton>
            </div>
          </div>
        </section>

        <section class="member-section">
          <div class="section-heading">
            <h2>待审批</h2>
            <IonNote>{{ management.pending.length }}</IonNote>
          </div>
          <IonList v-if="management.pending.length" inset>
            <IonItem v-for="member in management.pending" :key="member.userUid">
              <UserAvatar
                slot="start"
                :src="member.userAvatar"
                :alt="member.userName"
                telemetry-surface="workshop.management.pending"
                class="member-avatar"
              >
                <template #fallback>
                  <div class="member-avatar member-avatar--fallback">
                    {{ (member.userName || '坊')[0] }}
                  </div>
                </template>
              </UserAvatar>
              <IonLabel>
                <h2>{{ member.userName || '坊客' }}</h2>
                <p>{{ member.userUid }}</p>
              </IonLabel>
              <IonButton fill="clear" color="success" @click="decide(member, 'approve')">
                <IonIcon slot="icon-only" :icon="checkmarkOutline" />
              </IonButton>
              <IonButton fill="clear" color="danger" @click="decide(member, 'reject')">
                <IonIcon slot="icon-only" :icon="closeOutline" />
              </IonButton>
            </IonItem>
          </IonList>
        </section>

        <section class="member-section">
          <div class="section-heading">
            <h2>坊客</h2>
            <IonNote>{{ management.guests.length }}</IonNote>
          </div>
          <IonList v-if="management.guests.length" inset>
            <IonItem v-for="member in management.guests" :key="member.userUid">
              <IonLabel>
                <h2>{{ member.userName || '坊客' }}</h2>
                <p>{{ member.userUid }}</p>
              </IonLabel>
              <IonButton fill="clear" color="medium" @click="decide(member, 'remove')">
                <IonIcon slot="icon-only" :icon="personRemoveOutline" />
              </IonButton>
              <IonButton fill="clear" color="danger" @click="decide(member, 'block')">
                <IonIcon slot="icon-only" :icon="banOutline" />
              </IonButton>
            </IonItem>
          </IonList>
        </section>

        <section v-if="management.blocked.length" class="member-section">
          <div class="section-heading">
            <h2>已拉黑</h2>
            <IonNote>{{ management.blocked.length }}</IonNote>
          </div>
          <IonList inset>
            <IonItem v-for="member in management.blocked" :key="member.userUid">
              <IonLabel>
                <h2>{{ member.userName || '用户' }}</h2>
                <p>{{ member.userUid }}</p>
              </IonLabel>
              <IonButton fill="outline" size="small" @click="decide(member, 'unblock')">
                解除
              </IonButton>
            </IonItem>
          </IonList>
        </section>

        <IonList inset class="danger-zone">
          <IonItem button :detail="false" @click="toggleStatus">
            <IonIcon
              slot="start"
              :icon="powerOutline"
              :color="management.workshop.status === 'disabled' ? 'success' : 'danger'"
            />
            <IonLabel :color="management.workshop.status === 'disabled' ? 'success' : 'danger'">
              {{ management.workshop.status === 'disabled' ? '恢复个人工坊' : '停用个人工坊' }}
            </IonLabel>
          </IonItem>
        </IonList>
      </template>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.management-content {
  --background: var(--ion-background-color);
}

.management-loading {
  padding-top: 96px;
  display: flex;
  justify-content: center;
}

.create-workshop {
  padding: 56px 20px 40px;
}

.create-symbol {
  width: 64px;
  height: 64px;
  display: grid;
  place-items: center;
  border-radius: 18px;
  color: #fff;
  background: var(--ion-color-primary);
  font-size: 30px;
  transform: rotate(-5deg);
}

.create-workshop > span,
.workshop-identity > span,
.workshop-qr span {
  display: block;
  margin-top: 22px;
  color: var(--ion-color-medium);
  font-size: 11px;
  letter-spacing: 0.12em;
  text-transform: uppercase;
}

.create-workshop h1 {
  max-width: 520px;
  margin: 5px 0 10px;
  font-size: clamp(30px, 9vw, 46px);
  line-height: 1;
}

.create-workshop > p {
  max-width: 560px;
  color: var(--ion-color-medium);
  line-height: 1.55;
}

.workshop-identity {
  margin: 24px 20px;
  padding: 18px 20px;
  border-left: 4px solid var(--ion-color-primary);
  background: var(--ion-item-background);
}

.workshop-identity > span {
  margin-top: 0;
}

.workshop-identity strong {
  display: block;
  margin: 3px 0;
  font-family: 'SF Mono', 'Menlo', monospace;
  font-size: 24px;
  letter-spacing: 0.12em;
}

.workshop-qr {
  margin: 28px 20px 36px;
  display: grid;
  grid-template-columns: minmax(112px, 180px) 1fr;
  align-items: center;
  gap: 22px;
}

.workshop-qr img {
  width: 100%;
  border-radius: 18px;
  background: #fff;
}

.workshop-qr span {
  margin-top: 0;
}

.workshop-qr p {
  overflow-wrap: anywhere;
  color: var(--ion-color-medium);
  font-size: 13px;
}

.workshop-qr-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.member-section {
  margin-top: 28px;
}

.section-heading {
  padding: 0 20px 6px;
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}

.section-heading h2 {
  margin: 0;
  font-size: 20px;
}

.member-avatar {
  width: 40px;
  height: 40px;
  border-radius: 12px;
  object-fit: cover;
}

.member-avatar--fallback {
  display: grid;
  place-items: center;
  color: #fff;
  background: var(--ion-color-primary);
  font-weight: 700;
}

.danger-zone {
  margin-top: 40px;
  margin-bottom: 40px;
}

@media (max-width: 460px) {
  .workshop-qr {
    grid-template-columns: 132px 1fr;
    gap: 14px;
  }
}
</style>
