import assert from 'node:assert/strict'
// eslint-disable-next-line test/no-import-node-test
import { it } from 'node:test'
import { previewHeaders, validatePreviewTarget } from './live-target.mjs'

const receipt = {
  projectId: 'pages-duzdocfvhq4g',
  environment: 'Preview',
  status: 'Success',
  branch: 'codex/ios-native-app',
  deploymentId: 'dpiab6dfwnm5',
  commit: 'be0aafdb1018ef2a2f8c57062c8887b04e5a08dd',
  origin: 'https://yunlefun-apps-dpiab6dfwnm5.edgeone.cool',
}

it('accepts a receipt for the existing Apps preview project', () => {
  assert.equal(validatePreviewTarget(receipt).origin, receipt.origin)
})
it('requires fresh bounded platform cookies before any app sign-in', () => {
  const now = Date.now()
  const access = { cookie: 'eo_token=test-only; eo_time=1792120000', expiresAt: now + 3600000 }
  assert.deepEqual(previewHeaders({ ...receipt, previewAccess: access }, now), { Cookie: access.cookie })
  for (const changed of [
    undefined,
    { ...access, expiresAt: now },
    { ...access, expiresAt: now + 4 * 3600000 },
    { ...access, cookie: 'other=test-only; eo_time=1' },
    { ...access, cookie: 'eo_token=test-only; eo_time=1\r\nX-Injected: value' },
  ]) assert.throws(() => previewHeaders({ ...receipt, previewAccess: changed }, now))
})
it('rejects foreign, incomplete and misleading credential destinations', () => {
  for (const changed of [
    null,
    [],
    {},
    { ...receipt, status: 'Process' },
    { ...receipt, projectId: 'other-project' },
    { ...receipt, environment: 'Production' },
    { ...receipt, branch: 'main' },
    { ...receipt, commit: 'be0aafd' },
    { ...receipt, deploymentId: '../other' },
    ...[
      'http://yunlefun-apps-dpiab6dfwnm5.edgeone.cool',
      'https://unrelated.edgeone.cool',
      'https://yunlefun-apps-dpiab6dfwnm5.edgeone.cool.evil.test',
      'https://user:secret@yunlefun-apps-dpiab6dfwnm5.edgeone.cool',
      `${receipt.origin}:8443`,
      `${receipt.origin}/redirect`,
      `${receipt.origin}?next=other`,
      `${receipt.origin}#fragment`,
    ].map(origin => ({ ...receipt, origin })),
  ]) assert.throws(() => validatePreviewTarget(changed))
})
