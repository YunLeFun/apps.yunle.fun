import { describe, expect, it } from 'vitest'
import { getCloudbaseStoragePath } from '../../app/utils/cloudbase-storage-url'

describe('cloudbase storage URL', () => {
  const envId = 'yunlefun-8g7ybcxc7345c490'

  it('extracts the object path from an unsigned URL in the current environment', () => {
    expect(getCloudbaseStoragePath(
      'https://7975-yunlefun-8g7ybcxc7345c490-1325586649.tcb.qcloud.la/avatars/user%201.jpg',
      envId,
    )).toBe('avatars/user 1.jpg')
  })

  it('refreshes an existing signed URL using the stable object path', () => {
    expect(getCloudbaseStoragePath(
      'https://7975-yunlefun-8g7ybcxc7345c490-1325586649.tcb.qcloud.la/avatars/user.jpg?sign=expired&t=1',
      envId,
    )).toBe('avatars/user.jpg')
  })

  it('does not treat third-party or other-environment images as local storage', () => {
    expect(getCloudbaseStoragePath('https://avatars.githubusercontent.com/u/1', envId)).toBeNull()
    expect(getCloudbaseStoragePath(
      'https://bucket-another-env.tcb.qcloud.la/avatars/user.jpg',
      envId,
    )).toBeNull()
  })
})
