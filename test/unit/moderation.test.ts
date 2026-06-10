import { Buffer } from 'node:buffer'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const { textModerationMock, TmsClientMock } = vi.hoisted(() => {
  const textModerationMock = vi.fn()
  class TmsClientMock {
    TextModeration = textModerationMock
  }
  return { textModerationMock, TmsClientMock }
})

vi.mock('tencentcloud-sdk-nodejs-tms', () => ({
  tms: {
    v20201229: {
      Client: TmsClientMock,
    },
  },
}))

describe('moderation utils', () => {
  beforeEach(() => {
    vi.resetModules()
    vi.clearAllMocks()
    vi.stubGlobal('useRuntimeConfig', () => ({
      tencentApiSecretId: 'secret-id',
      tencentApiSecretKey: 'secret-key',
      tmsRegion: 'ap-guangzhou',
      tmsBizType: 'yunlefun',
    }))
  })

  it('buildModerationContent trims empty parts and truncates defensively', async () => {
    const { buildModerationContent } = await import('../../server/utils/moderation')
    const content = buildModerationContent([' title ', undefined, '', 'content'])
    expect(content).toBe('title\ncontent')

    const longContent = buildModerationContent(['x'.repeat(10_000)])
    expect(longContent).toHaveLength(9500)
  })

  it('maps TMS response fields into moderation result', async () => {
    const { moderateText } = await import('../../server/utils/moderation')
    textModerationMock.mockResolvedValueOnce({
      Suggestion: 'Pass',
      Label: 'Normal',
      RequestId: 'req-1',
      DetailResults: [{
        Suggestion: 'Block',
        Label: 'Ad',
        SubLabel: 'Contact',
        Keywords: ['加我'],
      }],
    })

    const result = await moderateText({
      content: '加我',
      userId: 'uid-1',
      dataId: 'review-cook-uid-1',
      scene: 'review',
    })

    expect(result).toEqual({
      suggestion: 'Block',
      label: 'Ad',
      subLabel: 'Contact',
      keywords: ['加我'],
      requestId: 'req-1',
    })
    expect(textModerationMock).toHaveBeenCalledWith(expect.objectContaining({
      Content: Buffer.from('加我', 'utf8').toString('base64'),
      BizType: 'yunlefun',
      DataId: 'review-cook-uid-1',
      Type: 'TEXT',
      SourceLanguage: 'zh',
    }))
  })

  it('fails safe to Review when TMS throws', async () => {
    const { moderateText } = await import('../../server/utils/moderation')
    textModerationMock.mockRejectedValueOnce(new Error('timeout'))

    const result = await moderateText({
      content: 'test',
      userId: 'uid-1',
      dataId: 'review-cook-uid-1',
      scene: 'review',
    })

    expect(result.suggestion).toBe('Review')
    expect(result.error).toBe('timeout')
  })
})
