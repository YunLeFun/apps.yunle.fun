import { parseWorkshopLink } from '~/utils/publicUrl'

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
