import { setResponseHeader } from 'h3'

export default defineEventHandler((event) => {
  const path = event.path.split('?')[0]
  if ((path === '/api/apps' || path.startsWith('/api/apps/'))
    && path !== '/api/apps/public' && !path.startsWith('/api/apps/public/')) {
    setResponseHeader(event, 'Cache-Control', 'private, no-store')
  }
})
