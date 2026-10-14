import {
  isWorkshopApiPath,
  setWorkshopNoStore,
} from '../utils/workshop-cache'

export default defineEventHandler((event) => {
  if (isWorkshopApiPath(event.path))
    setWorkshopNoStore(event)
})
