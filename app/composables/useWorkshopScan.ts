const WORKSHOP_ID_PATTERN = /^[2-9A-HJKMNP-Z]{6}$/

export function parseWorkshopLink(
  content: string,
  extraAllowedHosts: readonly string[] = [],
): string {
  const allowedHosts = new Set(['apps.yunle.fun', ...extraAllowedHosts])
  let url: URL
  try {
    url = new URL(content.trim())
  }
  catch {
    throw new Error('二维码不是有效的个人工坊链接')
  }
  if (url.protocol !== 'https:' || !allowedHosts.has(url.hostname))
    throw new Error('二维码不是云乐坊个人工坊链接')

  const match = url.pathname.match(/^\/w\/([^/]+)\/?$/)
  const workshopId = match?.[1]?.toUpperCase() || ''
  if (!WORKSHOP_ID_PATTERN.test(workshopId))
    throw new Error('个人工坊链接格式无效')
  return workshopId
}

export function useWorkshopScan() {
  const router = useRouter()
  const toast = useToast()

  async function handleScanResult(content: string) {
    try {
      const localHost = import.meta.client ? [window.location.hostname] : []
      const workshopId = parseWorkshopLink(content, localHost)
      await router.push(`/w/${workshopId}`)
    }
    catch (reason: unknown) {
      toast.showError(reason instanceof Error ? reason.message : '无法识别个人工坊二维码')
    }
  }

  return {
    handleScanResult,
  }
}
