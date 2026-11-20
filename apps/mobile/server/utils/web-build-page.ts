export const webBuildAppSlugPattern = /^web-build-([a-f0-9]{32})$/

const palettes = ['indigo', 'moss', 'clay', 'ocean'] as const

export interface WebBuildPage {
  title: string
  description: string
  palette: typeof palettes[number]
  sections: { title: string, text: string, expandable: boolean }[]
}

export interface WebBuildProject {
  id: string
  revision: number
  page: WebBuildPage
  prompts: string[]
  shareUrl: string | null
  publishedRevision: number | null
  updatedAt: number
  role: 'owner' | 'member'
  room?: WebBuildRoom
}

export interface WebBuildRoomMember {
  id: string
  name: string
}

export interface WebBuildRoomMessage {
  id: string
  author: WebBuildRoomMember
  kind: 'chat' | 'edit'
  text: string
  createdAt: number
}

export interface WebBuildRoom {
  members: WebBuildRoomMember[]
  viewerId: string
  messages: WebBuildRoomMessage[]
  inviteExpiresAt: number | null
  friendInvitesExpireAt?: number
}

export type WebBuildSummary = Pick<WebBuildProject, 'id' | 'shareUrl' | 'updatedAt' | 'role'> & { title: string }

export function parseWebBuildPage(input: unknown): WebBuildPage | null {
  if (!input || typeof input !== 'object')
    return null
  const { title, description, palette, sections } = input as Record<string, unknown>
  if (!validText(title, 50) || !validText(description, 220)
    || typeof palette !== 'string' || !palettes.includes(palette as WebBuildPage['palette'])
    || !Array.isArray(sections) || !sections.length || sections.length > 6) {
    return null
  }

  const parsed: WebBuildPage['sections'] = []
  for (const section of sections) {
    if (!section || typeof section !== 'object')
      return null
    const { title, text, expandable } = section
    if (!validText(title, 75) || !validText(text, 440) || typeof expandable !== 'boolean')
      return null
    parsed.push({ title: title.trim(), text: text.trim(), expandable })
  }
  return { title: title.trim(), description: description.trim(), palette: palette as WebBuildPage['palette'], sections: parsed }
}

function validText(value: unknown, limit: number): value is string {
  return typeof value === 'string' && value.length <= limit && Boolean(value.trim())
}
