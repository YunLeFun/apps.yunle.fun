import { Buffer } from 'node:buffer'
import { createHash, generateKeyPairSync, sign } from 'node:crypto'
import { createRequire } from 'node:module'
import { describe, expect, it } from 'vitest'

interface RsaPublicKey {
  verify: (digest: string, signature: string) => boolean
}

const require = createRequire(import.meta.url)
const listhenRequire = createRequire(require.resolve('listhen'))
const forge: {
  jsbn: { BigInteger: new (value: string, radix: number) => object }
  pki: {
    setRsaPublicKey: (modulus: object, exponent: object) => RsaPublicKey
    publicKeyFromPem: (pem: string) => RsaPublicKey
  }
} = listhenRequire('node-forge')

const message = Buffer.from('nested-digest-algorithm')
const digest = createHash('sha256').update(message).digest('latin1')

// Exponent 1 exposes the encoded message directly to the production verifier,
// keeping these ASN.1 fixtures deterministic (upstream forge PR #1158).
const fixtureKey = forge.pki.setRsaPublicKey(
  new forge.jsbn.BigInteger('f'.repeat(256), 16),
  new forge.jsbn.BigInteger('1', 10),
)

function createFixtureSignature(digestInfoPrefix: string) {
  const digestInfo = Buffer.from(digestInfoPrefix, 'hex').toString('latin1') + digest
  return `\x00\x01${'\xFF'.repeat(128 - digestInfo.length - 3)}\x00${digestInfo}`
}

describe('patched node-forge RSA signature verification', () => {
  it.each([
    ['with NULL parameters', '30343010060960864801650304020105000401000420'],
    ['without NULL parameters', '3032300e06096086480165030402010401000420'],
  ])('rejects an extra nested DigestAlgorithm element %s', (_name, prefix) => {
    expect(() => fixtureKey.verify(digest, createFixtureSignature(prefix)))
      .toThrow('ASN.1 object does not contain a valid RSASSA-PKCS1-v1_5 DigestInfo value.')
  })

  it.each([
    ['with NULL parameters', '3031300d060960864801650304020105000420'],
    ['without NULL parameters', '302f300b06096086480165030402010420'],
  ])('accepts valid DigestAlgorithm elements %s', (_name, prefix) => {
    expect(fixtureKey.verify(digest, createFixtureSignature(prefix))).toBe(true)
  })

  it('verifies a real RSA signature and rejects a changed message', () => {
    const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 1024 })
    const verifier = forge.pki.publicKeyFromPem(publicKey.export({ type: 'spki', format: 'pem' }).toString())
    const signature = sign('sha256', message, privateKey).toString('latin1')

    expect(verifier.verify(digest, signature)).toBe(true)
    expect(verifier.verify(createHash('sha256').update('changed-message').digest('latin1'), signature)).toBe(false)
  })
})
