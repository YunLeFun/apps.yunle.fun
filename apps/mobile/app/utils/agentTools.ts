import type { AgentToolDefinition } from '~/types/agent'

export const AGENT_SEARCH_APPS_TOOL_NAME = 'search_apps'

export const AGENT_SEARCH_APPS_TOOL_DEFINITION: AgentToolDefinition = {
  name: AGENT_SEARCH_APPS_TOOL_NAME,
  description: 'Search public approved YunLeFun apps and return compact app cards for the user to open, install, or inspect.',
  parameters: {
    type: 'object',
    properties: {
      query: {
        type: 'string',
        description: 'The user intent or keywords, such as "developer tools", "games", or "整理灵感".',
      },
      category: {
        type: 'string',
        description: 'Optional app category filter when the user explicitly asks for one.',
      },
      limit: {
        type: 'number',
        description: 'Maximum number of cards to return. Never request more than 6.',
      },
    },
    required: ['query'],
  },
}

export const AGENT_TOOL_DEFINITIONS = [
  AGENT_SEARCH_APPS_TOOL_DEFINITION,
]
