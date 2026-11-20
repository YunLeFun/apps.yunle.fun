import { defineEventHandler } from 'h3'
import { boardAppUrl } from '../../../app/utils/publicUrl'
import { conversationInvitePage } from '../../utils/conversation-invite-page'

export default defineEventHandler(event => conversationInvitePage(event, boardAppUrl(event.path), '联机五子棋', '在 iPhone 或 iPad 的云乐坊打开。登录后可以加入这局五子棋或观战。'))
