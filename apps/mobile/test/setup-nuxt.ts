import { beforeAll } from 'vitest'
import { useRouter } from '#app/composables/router'

beforeAll(async () => {
  await useRouter().isReady()
})
