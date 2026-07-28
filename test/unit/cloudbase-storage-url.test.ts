import { describe, expect, it } from 'vitest'
import { getPublicCloudbaseStorageUrl } from '../../app/utils/cloudbase-storage-url'

describe('cloudbase storage URL', () => {
  const envId = 'yunlefun-8g7ybcxc7345c490'
  const bucket = `7975-${envId}-1325586649`
  const publicOrigin = `https://${bucket}.tcb.qcloud.la`

  it('converts a trusted CloudBase file ID to its public avatar URL', () => {
    const fileID = `cloud://${envId}.${bucket}/avatars/user.jpg`
    expect(getPublicCloudbaseStorageUrl(fileID, envId, publicOrigin)).toBe(
      `https://${bucket}.tcb.qcloud.la/avatars/user.jpg`,
    )
  })

  it('removes an old signature from the current environment URL', () => {
    const signedUrl = 'https://7975-yunlefun-8g7ybcxc7345c490-1325586649.tcb.qcloud.la/avatars/user.jpg?sign=expired&t=1#avatar'
    expect(getPublicCloudbaseStorageUrl(signedUrl, envId, publicOrigin)).toBe(
      'https://7975-yunlefun-8g7ybcxc7345c490-1325586649.tcb.qcloud.la/avatars/user.jpg',
    )
  })

  it('does not treat third-party or other-environment images as local storage', () => {
    const thirdParty = 'https://avatars.githubusercontent.com/u/1?size=200'
    expect(getPublicCloudbaseStorageUrl(thirdParty, envId, publicOrigin)).toBe(thirdParty)
    const otherEnvironment = 'https://bucket-another-env.tcb.qcloud.la/avatars/user.jpg?sign=keep'
    expect(getPublicCloudbaseStorageUrl(otherEnvironment, envId, publicOrigin)).toBe(otherEnvironment)
  })

  it('keeps invalid URLs unchanged', () => {
    expect(getPublicCloudbaseStorageUrl('not-a-url', envId, publicOrigin)).toBe('not-a-url')
    expect(getPublicCloudbaseStorageUrl(
      'cloud://another-env.bucket/avatars/user.jpg',
      envId,
      publicOrigin,
    )).toBeNull()
  })

  it('does not guess a public URL without an explicit trusted origin', () => {
    const fileID = `cloud://${envId}.${bucket}/avatars/user.jpg`
    expect(getPublicCloudbaseStorageUrl(fileID, envId, '')).toBeNull()
  })
})
