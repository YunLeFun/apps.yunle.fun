import { describe, expect, it } from 'vitest'
import { hasVerifiedPhone } from '../../server/utils/cloudbase-auth'

describe('hasVerifiedPhone', () => {
  it('accepts a CloudBase phone-number provider session', () => {
    expect(hasVerifiedPhone({}, {
      provider_type: 'phone_number',
      phone_number: '+86 ***********',
    })).toBe(true)
  })

  it('requires both the phone provider and a phone number', () => {
    expect(hasVerifiedPhone({}, { provider_type: 'phone_number' })).toBe(false)
    expect(hasVerifiedPhone({}, { phone_number: '+86 ***********' })).toBe(false)
  })

  it('honors an explicit unverified claim', () => {
    expect(hasVerifiedPhone({}, {
      phone_verified: false,
      provider_type: 'phone_number',
      phone_number: '+86 ***********',
    })).toBe(false)
  })
})
