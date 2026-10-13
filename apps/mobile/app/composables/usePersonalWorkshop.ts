import type {
  JoinWorkshopResult,
  WorkshopJoinPolicy,
  WorkshopManagementView,
  WorkshopPublicInfo,
  WorkshopStatus,
  WorkshopView,
} from '~/types/workshop'

export function usePersonalWorkshop() {
  const { $api } = useNuxtApp()

  async function getView(workshopId: string): Promise<WorkshopView> {
    return $api<WorkshopView>(`/api/workshops/${encodeURIComponent(workshopId)}`)
  }

  async function join(workshopId: string): Promise<JoinWorkshopResult> {
    return $api<JoinWorkshopResult>(`/api/workshops/${encodeURIComponent(workshopId)}/join`, {
      method: 'POST',
    })
  }

  async function leave(workshopId: string): Promise<void> {
    await $api(`/api/workshops/${encodeURIComponent(workshopId)}/leave`, {
      method: 'POST',
    })
  }

  async function getManagement(): Promise<WorkshopManagementView | null> {
    const response = await $api<{ management: WorkshopManagementView | null }>('/api/workshops/mine')
    return response.management
  }

  async function create(input: { name?: string, description?: string }): Promise<WorkshopManagementView['workshop']> {
    const response = await $api<{ workshop: WorkshopManagementView['workshop'] }>('/api/workshops', {
      method: 'POST',
      body: input,
    })
    return response.workshop
  }

  async function update(
    workshopId: string,
    input: {
      name?: string
      description?: string
      joinPolicy?: WorkshopJoinPolicy
      status?: WorkshopStatus
    },
  ): Promise<WorkshopManagementView['workshop']> {
    const response = await $api<{ workshop: WorkshopManagementView['workshop'] }>(
      `/api/workshops/${encodeURIComponent(workshopId)}`,
      {
        method: 'PATCH',
        body: input,
      },
    )
    return response.workshop
  }

  async function decide(
    workshopId: string,
    userUid: string,
    action: 'approve' | 'reject' | 'remove' | 'block' | 'unblock',
  ): Promise<void> {
    await $api(
      `/api/workshops/${encodeURIComponent(workshopId)}/members/${encodeURIComponent(userUid)}`,
      {
        method: 'POST',
        body: { action },
      },
    )
  }

  async function getJoined(): Promise<WorkshopPublicInfo[]> {
    const response = await $api<{ items: WorkshopPublicInfo[] }>('/api/workshops/joined')
    return response.items
  }

  return {
    getView,
    join,
    leave,
    getManagement,
    create,
    update,
    decide,
    getJoined,
  }
}
