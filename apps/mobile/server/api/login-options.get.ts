import { setResponseHeader } from 'h3'
import { useCloudbaseAdmin } from '../utils/cloudbase-admin'

/** Anonymous read model: never return the document or its operator metadata. */
export default defineEventHandler(async (event) => {
  setResponseHeader(event, 'Cache-Control', 'no-store')
  try {
    const { data } = await useCloudbaseAdmin().db.collection('app_login_options').doc('web').get()
    const options: unknown = Array.isArray(data) ? data[0] : data
    return {
      weChatLoginVisible: !!options && typeof options === 'object'
        && 'weChatLoginVisible' in options && options.weChatLoginVisible === true,
    }
  }
  catch {
    // Missing or unavailable configuration must never show a broken login option.
    return { weChatLoginVisible: false }
  }
})
