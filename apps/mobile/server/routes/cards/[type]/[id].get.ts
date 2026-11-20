import { defineEventHandler } from 'h3'
import { conversationCardAppUrl } from '../../../../app/utils/publicUrl'
import { conversationInvitePage } from '../../../utils/conversation-invite-page'

export default defineEventHandler(event => conversationInvitePage(event, conversationCardAppUrl(event.path), '云乐坊共享卡片', '在 iPhone 或 iPad 的云乐坊打开。登录后可以继续操作这张卡片。'))
