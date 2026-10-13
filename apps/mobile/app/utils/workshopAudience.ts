import type { AppAudience } from '~/types/app'

interface PersonalWorkshopGateway {
  getManagement: () => Promise<unknown | null>
  create: (input: { name?: string, description?: string }) => Promise<unknown>
}

export async function ensureWorkshopForAudience(
  audience: AppAudience,
  workshopModule: PersonalWorkshopGateway,
): Promise<boolean> {
  if (audience !== 'workshop')
    return false

  const management = await workshopModule.getManagement()
  if (management)
    return false

  await workshopModule.create({})
  return true
}
