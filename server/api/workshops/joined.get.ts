import { setResponseHeader } from 'h3'
import { requireRegisteredCloudbaseUser } from '../../utils/cloudbase-auth'
import { listJoinedWorkshops } from '../../utils/personal-workshops'

export default defineEventHandler(async (event) => {
  const user = await requireRegisteredCloudbaseUser(event)
  setResponseHeader(event, 'Cache-Control', 'private, no-store')
  const workshops = await listJoinedWorkshops(user)
  return {
    items: workshops.map(workshop => ({
      _id: workshop._id,
      ownerName: workshop.ownerName,
      ownerAvatar: workshop.ownerAvatar,
      name: workshop.name,
      description: workshop.description,
      joinPolicy: workshop.joinPolicy,
      status: workshop.status,
    })),
  }
})
