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
  checkmarkCircleOutline,
  checkmarkOutline,
  closeOutline,
  copyOutline,
  eyeOutline,
  informationCircleOutline,
  peopleOutline,
  personRemoveOutline,
  powerOutline,
  qrCodeOutline,
  shareOutline,
} from 'ionicons/icons'
import QRCode from 'qrcode'
import { buildPublicWorkshopUrl } from '~/utils/publicUrl'
import { getRequestErrorInfo } from '~/utils/requestError'

const router = useRouter()
const runtimeConfig = useRuntimeConfig()
const workshopModule = usePersonalWorkshop()
const toast = useToast()
const loading = ref(true)
const saving = ref(false)
const activeMemberAction = ref('')
const management = ref<WorkshopManagementView | null>(null)
const name = ref('')
const description = ref('')
const joinPolicy = ref<WorkshopJoinPolicy>('approval')
const qrcodeDataUrl = ref('')

const workshopUrl = computed(() => {
  const id = management.value?.workshop._id
  if (!id)
    return ''
  return buildPublicWorkshopUrl(id, runtimeConfig.public.appBaseUrl)
})

const hasUnsavedChanges = computed(() => {
  const workshop = management.value?.workshop
  if (!workshop)
    return false

  return name.value.trim() !== workshop.name
    || description.value.trim() !== (workshop.description || '')
    || joinPolicy.value !== workshop.joinPolicy
})

const joinPolicySummary = computed(() => {
  switch (joinPolicy.value) {
    case 'open':
      return '获得链接的登录用户无需审批即可加入。'
    case 'closed':
      return '新用户暂时无法申请，现有坊客不受影响。'
    default:
      return '新用户提交申请后，需要你在这里审批。'
  }
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
    toast.showSuccess('个人工坊已开启')
    await load()
  }
  catch (reason: unknown) {
    const requestError = getRequestErrorInfo(reason, '创建失败')
    toast.showError(requestError.message, requestError.copyText)
  }
  finally {
    saving.value = false
  }
}

async function saveWorkshop() {
  if (!management.value || !hasUnsavedChanges.value || !name.value.trim())
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
  const key = memberActionKey(member, action)
  activeMemberAction.value = key
  try {
    await workshopModule.decide(
      management.value.workshop._id,
      member.userUid,
      action,
    )
    applyMemberAction(member, action)
    toast.showSuccess(actionLabel(action))
  }
  catch (reason: unknown) {
    toast.showError(reason instanceof Error ? reason.message : '操作失败')
  }
  finally {
    activeMemberAction.value = ''
  }
}

async function shareWorkshop() {
  if (!workshopUrl.value)
    return
  try {
    if (navigator.share) {
      await navigator.share({
        title: management.value?.workshop.name || '个人工坊',
        text: '打开链接申请加入我的个人工坊',
        url: workshopUrl.value,
      })
      return
    }
  }
  catch (reason: unknown) {
    if (reason instanceof DOMException && reason.name === 'AbortError')
      return
  }
  await copyWorkshopUrl()
}

async function copyWorkshopUrl() {
  if (!workshopUrl.value)
    return
  try {
    await navigator.clipboard.writeText(workshopUrl.value)
    toast.showSuccess('在线工坊链接已复制')
  }
  catch {
    toast.showError('复制失败，请长按链接手动复制', workshopUrl.value)
  }
}

function openWorkshop() {
  const id = management.value?.workshop._id
  if (id)
    router.push(`/w/${id}`)
}

async function confirmMemberAction(
  member: WorkshopMembership,
  action: 'remove' | 'block',
) {
  const memberName = member.userName || '这位坊客'
  const alert = await alertController.create({
    header: action === 'block' ? `拉黑${memberName}` : `移除${memberName}`,
    message: action === 'block'
      ? '对方将无法再次申请加入，除非你之后解除拉黑。'
      : '对方会失去工坊访问权限，但仍可再次申请加入。',
    buttons: [
      { text: '取消', role: 'cancel' },
      {
        text: action === 'block' ? '确认拉黑' : '确认移除',
        role: 'destructive',
        handler: () => decide(member, action),
      },
    ],
  })
  await alert.present()
}

function applyMemberAction(
  member: WorkshopMembership,
  action: 'approve' | 'reject' | 'remove' | 'block' | 'unblock',
) {
  const current = management.value
  if (!current)
    return

  const removeFrom = (members: WorkshopMembership[]) => {
    const index = members.findIndex(item => item.userUid === member.userUid)
    if (index >= 0)
      members.splice(index, 1)
  }

  if (action === 'approve') {
    removeFrom(current.pending)
    current.guests.unshift({
      ...member,
      status: 'active',
      joinedAt: Date.now(),
      updatedAt: Date.now(),
    })
    return
  }

  if (action === 'reject') {
    removeFrom(current.pending)
    return
  }

  if (action === 'remove') {
    removeFrom(current.guests)
    return
  }

  if (action === 'block') {
    removeFrom(current.guests)
    current.blocked.unshift({
      ...member,
      status: 'blocked',
      updatedAt: Date.now(),
    })
    return
  }

  removeFrom(current.blocked)
}

function memberActionKey(
  member: WorkshopMembership,
  action: 'approve' | 'reject' | 'remove' | 'block' | 'unblock',
) {
  return `${member.userUid}:${action}`
}

function isMemberBusy(member: WorkshopMembership) {
  return activeMemberAction.value.startsWith(`${member.userUid}:`)
}

function memberMeta(member: WorkshopMembership, kind: 'pending' | 'guest' | 'blocked') {
  const timestamp = kind === 'pending'
    ? member.requestedAt
    : kind === 'guest'
      ? member.joinedAt
      : member.updatedAt
  const label = kind === 'pending' ? '申请于' : kind === 'guest' ? '加入于' : '拉黑于'

  if (!timestamp)
    return `用户 ID · ${member.userUid}`

  return `${label} ${new Intl.DateTimeFormat('zh-CN', {
    month: 'short',
    day: 'numeric',
  }).format(timestamp)}`
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
        <IonTitle>管理个人工坊</IonTitle>
        <IonButtons v-if="management" slot="end">
          <IonButton
            :disabled="saving || !name.trim() || !hasUnsavedChanges"
            :strong="hasUnsavedChanges"
            @click="saveWorkshop"
          >
            <IonSpinner v-if="saving" name="crescent" />
            <span v-else>保存</span>
          </IonButton>
        </IonButtons>
      </IonToolbar>
    </IonHeader>

    <IonContent :fullscreen="true" class="management-content">
      <AppPageLoading v-if="loading" label="正在加载个人工坊" />

      <div v-else-if="!management" class="create-workshop">
        <div class="create-symbol">
          <IonIcon :icon="qrCodeOutline" />
        </div>
        <span>仅需创建一次</span>
        <h1>开启你的个人工坊</h1>
        <p>系统会使用默认名称并生成固定工坊号，名称和简介可以稍后修改。</p>
        <IonButton :disabled="saving" @click="createWorkshop">
          <IonSpinner v-if="saving" name="crescent" />
          开启个人工坊
        </IonButton>
      </div>

      <template v-else>
        <main class="management-shell">
          <section class="workshop-overview">
            <div class="overview-heading">
              <div>
                <div class="status-line">
                  <span
                    class="status-dot"
                    :class="{ 'status-dot--disabled': management.workshop.status === 'disabled' }"
                  />
                  {{ management.workshop.status === 'active' ? '工坊开放中' : '工坊已停用' }}
                </div>
                <h1>{{ management.workshop.name }}</h1>
                <p>{{ management.workshop.description || '还没有填写工坊简介。' }}</p>
              </div>
              <IonButton fill="outline" size="small" @click="openWorkshop">
                <IonIcon slot="start" :icon="eyeOutline" />
                查看工坊
              </IonButton>
            </div>

            <div class="overview-stats">
              <div>
                <span>固定工坊号</span>
                <strong class="workshop-id">{{ management.workshop._id }}</strong>
              </div>
              <div>
                <span>坊客</span>
                <strong>{{ management.guests.length }}</strong>
              </div>
              <div :class="{ 'stat--attention': management.pending.length }">
                <span>待审批</span>
                <strong>{{ management.pending.length }}</strong>
              </div>
            </div>
          </section>

          <section class="management-panel share-panel">
            <div class="share-qr">
              <img v-if="qrcodeDataUrl" :src="qrcodeDataUrl" alt="个人工坊在线分享二维码">
            </div>
            <div class="share-copy">
              <div class="section-heading">
                <div>
                  <h2>邀请坊客</h2>
                  <p>扫码或打开链接，即可在 App 外查看并申请加入。</p>
                </div>
              </div>
              <button class="public-url" type="button" @click="copyWorkshopUrl">
                <span>{{ workshopUrl }}</span>
                <IonIcon :icon="copyOutline" />
              </button>
              <div class="share-actions">
                <IonButton @click="shareWorkshop">
                  <IonIcon slot="start" :icon="shareOutline" />
                  分享工坊
                </IonButton>
                <IonButton fill="outline" @click="copyWorkshopUrl">
                  <IonIcon slot="start" :icon="copyOutline" />
                  复制链接
                </IonButton>
              </div>
              <div class="online-link-note">
                <IonIcon :icon="checkmarkCircleOutline" />
                二维码固定使用 apps.yunle.fun 在线地址
              </div>
            </div>
          </section>

          <section class="management-panel settings-panel">
            <div class="section-heading">
              <div>
                <h2>工坊设置</h2>
                <p>名称和简介会展示给所有访问工坊的人。</p>
              </div>
              <span v-if="hasUnsavedChanges" class="unsaved-label">有未保存更改</span>
            </div>

            <IonList class="settings-list">
              <IonItem>
                <IonInput
                  v-model="name"
                  label="名称"
                  label-placement="stacked"
                  :maxlength="40"
                  placeholder="给工坊起一个容易识别的名字"
                />
              </IonItem>
              <IonItem>
                <IonTextarea
                  v-model="description"
                  label="简介"
                  label-placement="stacked"
                  :maxlength="200"
                  :rows="3"
                  placeholder="简单介绍工坊里的内容"
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

            <div class="settings-hint">
              <IonIcon :icon="informationCircleOutline" />
              <span>{{ joinPolicySummary }}</span>
            </div>
            <div class="settings-footer">
              <IonNote>工坊号和分享链接不会随名称修改。</IonNote>
              <IonButton
                :disabled="saving || !name.trim() || !hasUnsavedChanges"
                @click="saveWorkshop"
              >
                <IonSpinner v-if="saving" name="crescent" />
                <template v-else>
                  保存更改
                </template>
              </IonButton>
            </div>
          </section>

          <section class="management-panel members-panel">
            <div class="section-heading">
              <div>
                <h2>成员管理</h2>
                <p>{{ management.guests.length }} 位坊客，{{ management.pending.length }} 个待处理申请。</p>
              </div>
              <IonIcon class="section-icon" :icon="peopleOutline" />
            </div>

            <div class="member-group">
              <div class="member-group-heading">
                <h3>待审批</h3>
                <span>{{ management.pending.length }}</span>
              </div>
              <IonList v-if="management.pending.length" class="member-list">
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
                    <p>{{ memberMeta(member, 'pending') }}</p>
                  </IonLabel>
                  <IonButton
                    size="small"
                    color="success"
                    :disabled="isMemberBusy(member)"
                    :aria-label="`通过 ${member.userName || '坊客'} 的申请`"
                    @click="decide(member, 'approve')"
                  >
                    <IonSpinner
                      v-if="activeMemberAction === memberActionKey(member, 'approve')"
                      name="crescent"
                    />
                    <template v-else>
                      <IonIcon slot="start" :icon="checkmarkOutline" />
                      通过
                    </template>
                  </IonButton>
                  <IonButton
                    size="small"
                    fill="clear"
                    color="danger"
                    :disabled="isMemberBusy(member)"
                    :aria-label="`拒绝 ${member.userName || '坊客'} 的申请`"
                    @click="decide(member, 'reject')"
                  >
                    <IonSpinner
                      v-if="activeMemberAction === memberActionKey(member, 'reject')"
                      name="crescent"
                    />
                    <template v-else>
                      <IonIcon slot="start" :icon="closeOutline" />
                      拒绝
                    </template>
                  </IonButton>
                </IonItem>
              </IonList>
              <div v-else class="member-empty">
                <IonIcon :icon="checkmarkCircleOutline" />
                暂无待审批申请
              </div>
            </div>

            <div class="member-group">
              <div class="member-group-heading">
                <h3>坊客</h3>
                <span>{{ management.guests.length }}</span>
              </div>
              <IonList v-if="management.guests.length" class="member-list">
                <IonItem v-for="member in management.guests" :key="member.userUid">
                  <UserAvatar
                    slot="start"
                    :src="member.userAvatar"
                    :alt="member.userName"
                    telemetry-surface="workshop.management.guests"
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
                    <p>{{ memberMeta(member, 'guest') }}</p>
                  </IonLabel>
                  <IonButton
                    size="small"
                    fill="clear"
                    color="medium"
                    :disabled="isMemberBusy(member)"
                    :aria-label="`移除 ${member.userName || '坊客'}`"
                    @click="confirmMemberAction(member, 'remove')"
                  >
                    <IonIcon slot="start" :icon="personRemoveOutline" />
                    移除
                  </IonButton>
                  <IonButton
                    size="small"
                    fill="clear"
                    color="danger"
                    :disabled="isMemberBusy(member)"
                    :aria-label="`拉黑 ${member.userName || '坊客'}`"
                    @click="confirmMemberAction(member, 'block')"
                  >
                    <IonIcon slot="start" :icon="banOutline" />
                    拉黑
                  </IonButton>
                </IonItem>
              </IonList>
              <div v-else class="member-empty">
                <IonIcon :icon="peopleOutline" />
                还没有坊客，分享上方二维码邀请朋友加入
              </div>
            </div>

            <div v-if="management.blocked.length" class="member-group">
              <div class="member-group-heading">
                <h3>已拉黑</h3>
                <span>{{ management.blocked.length }}</span>
              </div>
              <IonList class="member-list">
                <IonItem v-for="member in management.blocked" :key="member.userUid">
                  <UserAvatar
                    slot="start"
                    :src="member.userAvatar"
                    :alt="member.userName"
                    telemetry-surface="workshop.management.blocked"
                    class="member-avatar"
                  >
                    <template #fallback>
                      <div class="member-avatar member-avatar--fallback member-avatar--blocked">
                        {{ (member.userName || '用')[0] }}
                      </div>
                    </template>
                  </UserAvatar>
                  <IonLabel>
                    <h2>{{ member.userName || '用户' }}</h2>
                    <p>{{ memberMeta(member, 'blocked') }}</p>
                  </IonLabel>
                  <IonButton
                    fill="outline"
                    size="small"
                    :disabled="isMemberBusy(member)"
                    @click="decide(member, 'unblock')"
                  >
                    <IonSpinner
                      v-if="activeMemberAction === memberActionKey(member, 'unblock')"
                      name="crescent"
                    />
                    <template v-else>
                      解除拉黑
                    </template>
                  </IonButton>
                </IonItem>
              </IonList>
            </div>
          </section>

          <section class="management-panel danger-panel">
            <div>
              <h2>{{ management.workshop.status === 'disabled' ? '恢复个人工坊' : '停用个人工坊' }}</h2>
              <p>
                {{ management.workshop.status === 'disabled'
                  ? '恢复后，原有坊客会重新获得工坊作品访问权限。'
                  : '停用后，成员关系和申请记录会保留，坊客暂时无法访问作品。' }}
              </p>
            </div>
            <IonButton
              fill="outline"
              :color="management.workshop.status === 'disabled' ? 'success' : 'danger'"
              @click="toggleStatus"
            >
              <IonIcon slot="start" :icon="powerOutline" />
              {{ management.workshop.status === 'disabled' ? '恢复工坊' : '停用工坊' }}
            </IonButton>
          </section>
        </main>
      </template>
    </IonContent>
  </IonPage>
</template>

<style scoped>
.management-content {
  --background: var(--ion-background-color);
}

.create-workshop {
  width: min(100%, 720px);
  margin: 0 auto;
  padding: 64px 24px 48px;
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

.create-workshop > span {
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

.management-shell {
  width: min(100%, 880px);
  margin: 0 auto;
  padding: 24px 20px calc(48px + var(--ion-safe-area-bottom, 0px));
}

.workshop-overview,
.management-panel {
  border: 1px solid rgb(127 127 127 / 16%);
  border-radius: 24px;
  background: var(--ion-item-background, #fff);
  box-shadow: 0 12px 36px rgb(0 0 0 / 4%);
}

.workshop-overview {
  overflow: hidden;
  padding: 24px;
}

.overview-heading {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 20px;
}

.status-line {
  display: flex;
  align-items: center;
  gap: 7px;
  color: var(--ion-color-medium);
  font-size: 13px;
  font-weight: 600;
}

.status-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--ion-color-success);
  box-shadow: 0 0 0 4px rgb(var(--ion-color-success-rgb) / 12%);
}

.status-dot--disabled {
  background: var(--ion-color-medium);
  box-shadow: 0 0 0 4px rgb(var(--ion-color-medium-rgb) / 12%);
}

.overview-heading h1 {
  margin: 8px 0 5px;
  font-size: clamp(26px, 5vw, 34px);
  line-height: 1.15;
  letter-spacing: -0.02em;
}

.overview-heading p,
.section-heading p,
.danger-panel p {
  margin: 0;
  color: var(--ion-color-medium);
  line-height: 1.5;
}

.overview-stats {
  margin: 24px -24px -24px;
  padding: 18px 24px;
  display: flex;
  gap: 0;
  border-top: 1px solid rgb(127 127 127 / 14%);
  background: rgb(127 127 127 / 4%);
}

.overview-stats > div {
  min-width: 0;
  padding: 0 22px;
  display: flex;
  flex: 1;
  flex-direction: column;
  gap: 5px;
  border-left: 1px solid rgb(127 127 127 / 14%);
}

.overview-stats > div:first-child {
  padding-left: 0;
  flex: 2;
  border-left: 0;
}

.overview-stats span {
  color: var(--ion-color-medium);
  font-size: 12px;
}

.overview-stats strong {
  font-size: 22px;
  line-height: 1;
}

.overview-stats .workshop-id {
  overflow: hidden;
  font-family: 'SF Mono', 'Menlo', monospace;
  font-size: 18px;
  letter-spacing: 0.1em;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.overview-stats .stat--attention strong {
  color: var(--ion-color-warning-shade);
}

.management-panel {
  margin-top: 18px;
  padding: 24px;
}

.share-panel {
  display: grid;
  grid-template-columns: 188px minmax(0, 1fr);
  gap: 28px;
  align-items: center;
}

.share-qr {
  padding: 10px;
  border: 1px solid rgb(127 127 127 / 14%);
  border-radius: 20px;
  background: #fff;
  box-shadow: 0 8px 24px rgb(0 0 0 / 7%);
}

.share-qr img {
  display: block;
  width: 100%;
  aspect-ratio: 1;
}

.section-heading {
  display: flex;
  justify-content: space-between;
  gap: 16px;
}

.section-heading h2,
.danger-panel h2 {
  margin: 0 0 5px;
  font-size: 21px;
  letter-spacing: -0.01em;
}

.section-heading p,
.danger-panel p {
  font-size: 14px;
}

.public-url {
  width: 100%;
  margin: 18px 0 14px;
  padding: 11px 12px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  border: 1px solid rgb(127 127 127 / 18%);
  border-radius: 12px;
  color: var(--ion-text-color);
  background: rgb(127 127 127 / 6%);
  font:
    12px/1.35 'SF Mono',
    'Menlo',
    monospace;
  text-align: left;
}

.public-url span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.public-url ion-icon {
  flex: 0 0 auto;
  color: var(--ion-color-primary);
  font-size: 18px;
}

.share-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.share-actions ion-button {
  margin: 0;
  --border-radius: 12px;
}

.online-link-note,
.settings-hint,
.member-empty {
  display: flex;
  align-items: center;
  gap: 7px;
  color: var(--ion-color-medium);
  font-size: 12px;
}

.online-link-note {
  margin-top: 13px;
}

.online-link-note ion-icon {
  color: var(--ion-color-success);
  font-size: 17px;
}

.unsaved-label {
  flex: 0 0 auto;
  padding: 5px 9px;
  border-radius: 999px;
  color: var(--ion-color-warning-shade);
  background: rgb(var(--ion-color-warning-rgb) / 14%);
  font-size: 11px;
  font-weight: 650;
}

.settings-list,
.member-list {
  margin-top: 18px;
  padding: 0;
  border: 1px solid rgb(127 127 127 / 16%);
  border-radius: 16px;
  background: transparent;
}

.settings-list ion-item,
.member-list ion-item {
  --background: transparent;
  --border-color: rgb(127 127 127 / 13%);
}

.settings-list ion-item:last-child,
.member-list ion-item:last-child {
  --border-color: transparent;
}

.settings-hint {
  margin-top: 12px;
  padding: 0 4px;
  align-items: flex-start;
  line-height: 1.45;
}

.settings-hint ion-icon {
  margin-top: 1px;
  flex: 0 0 auto;
  color: var(--ion-color-primary);
  font-size: 17px;
}

.settings-footer {
  margin-top: 20px;
  padding-top: 18px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  border-top: 1px solid rgb(127 127 127 / 13%);
}

.settings-footer ion-button {
  margin: 0;
  flex: 0 0 auto;
  --border-radius: 12px;
}

.section-icon {
  flex: 0 0 auto;
  color: var(--ion-color-primary);
  font-size: 25px;
}

.member-group {
  margin-top: 24px;
}

.member-group-heading {
  padding: 0 3px;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.member-group-heading h3 {
  margin: 0;
  font-size: 15px;
}

.member-group-heading span {
  min-width: 24px;
  padding: 3px 7px;
  border-radius: 999px;
  color: var(--ion-color-medium);
  background: rgb(127 127 127 / 10%);
  font-size: 11px;
  text-align: center;
}

.member-list {
  margin-top: 9px;
}

.member-avatar {
  width: 42px;
  height: 42px;
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

.member-avatar--blocked {
  background: var(--ion-color-medium);
}

.member-empty {
  min-height: 62px;
  margin-top: 9px;
  padding: 14px 16px;
  justify-content: center;
  border: 1px dashed rgb(127 127 127 / 24%);
  border-radius: 14px;
  text-align: center;
}

.member-empty ion-icon {
  flex: 0 0 auto;
  font-size: 18px;
}

.danger-panel {
  margin-bottom: 8px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 24px;
  box-shadow: none;
}

.danger-panel ion-button {
  margin: 0;
  flex: 0 0 auto;
  --border-radius: 12px;
}

@media (max-width: 640px) {
  .management-shell {
    padding: 16px 12px calc(40px + var(--ion-safe-area-bottom, 0px));
  }

  .workshop-overview,
  .management-panel {
    border-radius: 20px;
  }

  .workshop-overview,
  .management-panel {
    padding: 19px;
  }

  .overview-heading {
    flex-direction: column;
    gap: 12px;
  }

  .overview-heading ion-button {
    margin: 0;
  }

  .overview-stats {
    margin: 20px -19px -19px;
    padding: 16px 19px;
  }

  .overview-stats > div {
    padding: 0 12px;
  }

  .share-panel {
    grid-template-columns: 116px minmax(0, 1fr);
    gap: 16px;
    align-items: start;
  }

  .share-qr {
    padding: 7px;
    border-radius: 16px;
  }

  .public-url {
    margin-top: 14px;
  }

  .online-link-note {
    grid-column: 1 / -1;
  }

  .settings-footer,
  .danger-panel {
    align-items: stretch;
    flex-direction: column;
  }

  .settings-footer ion-button,
  .danger-panel ion-button {
    align-self: flex-start;
  }
}

@media (max-width: 420px) {
  .share-panel {
    grid-template-columns: 96px minmax(0, 1fr);
    gap: 13px;
  }

  .share-copy .section-heading p {
    display: none;
  }

  .share-actions {
    flex-direction: column;
    align-items: stretch;
  }

  .share-actions ion-button {
    width: 100%;
  }

  .overview-stats > div {
    padding: 0 9px;
  }

  .overview-stats strong {
    font-size: 19px;
  }

  .overview-stats .workshop-id {
    font-size: 15px;
  }

  .member-list ion-button {
    margin-inline: 0;
    font-size: 12px;
  }
}
</style>
