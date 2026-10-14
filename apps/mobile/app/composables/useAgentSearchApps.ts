import type { SearchAppsInput } from '../../server/utils/agent-search-apps'
import type { AgentAppCard } from '~/types/agent'

interface SearchAppsResponse {
  code?: number
  message?: string
  data?: {
    apps?: AgentAppCard[]
  }
}

export function useAgentSearchApps() {
  const { $api } = useNuxtApp()

  async function searchApps(input: SearchAppsInput): Promise<AgentAppCard[]> {
    const res = await $api<SearchAppsResponse>('/api/agent/search-apps', {
      method: 'POST',
      body: input,
    })

    return Array.isArray(res.data?.apps) ? res.data.apps : []
  }

  return {
    searchApps,
  }
}
