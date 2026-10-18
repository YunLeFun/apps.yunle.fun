import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const script = fileURLToPath(new URL('../../../ios/scripts/testflight.sh', import.meta.url))

function runStage(stage: string, bundleId: string, internalOnly: boolean | null) {
  const dir = mkdtempSync(join(tmpdir(), 'ylf-testflight-test-'))
  try {
    const output = join(dir, 'release')
    mkdirSync(join(output, 'export'), { recursive: true })
    const fixture = spawnSync('python3', ['-c', `
import json, plistlib, sys, zipfile
info = {'CFBundleIdentifier': sys.argv[2], 'CFBundleShortVersionString': '0.2.0', 'CFBundleVersion': '2'}
flag = json.loads(sys.argv[3])
if flag is not None:
    info['TFInternalTestingOnly'] = flag
with zipfile.ZipFile(sys.argv[1], 'w') as archive:
    archive.writestr('Payload/YunleFun.app/Info.plist', plistlib.dumps(info))
`, join(output, 'export/YunleFun.ipa'), bundleId, JSON.stringify(internalOnly)])
    expect(fixture.status, fixture.stderr?.toString()).toBe(0)

    // Every altool invocation is intercepted; these tests never contact Apple.
    writeFileSync(join(dir, 'xcrun'), '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$YLF_TOOL_CALLS"\n', { mode: 0o755 })
    writeFileSync(join(dir, 'AuthKey_TEST.p8'), 'test fixture, not a private key')
    const calls = join(dir, 'calls.txt')
    const result = spawnSync('bash', [script, stage], {
      encoding: 'utf8',
      env: {
        ...process.env,
        PATH: `${dir}:${process.env.PATH}`,
        IOS_TESTFLIGHT_DIR: output,
        IOS_BUNDLE_ID: 'fun.yunle.apps',
        ASC_KEY_ID: 'TEST',
        ASC_ISSUER_ID: 'test-issuer',
        ASC_KEY_P8: join(dir, 'AuthKey_TEST.p8'),
        YUNLEFUN_CONFIRM_UPLOAD: '1',
        YLF_TOOL_CALLS: calls,
      },
    })
    return { ...result, calls: existsSync(calls) ? readFileSync(calls, 'utf8') : '' }
  }
  finally {
    rmSync(dir, { recursive: true, force: true })
  }
}

describe('native TestFlight package boundary', () => {
  it.each(['validate', 'upload'])('rejects a non-internal IPA before %s reaches Apple', (stage) => {
    for (const flag of [false, null]) {
      const result = runStage(stage, 'fun.yunle.apps', flag)
      expect(result.status).not.toBe(0)
      expect(result.stderr).toContain('TFInternalTestingOnly=true')
      expect(result.calls).toBe('')
    }
  })

  it('rejects an internal IPA belonging to a different app', () => {
    const result = runStage('upload', 'cn.yunyoujun.life', true)
    expect(result.status).not.toBe(0)
    expect(result.stderr).toContain('Bundle ID')
    expect(result.calls).toBe('')
  })

  it.each(['validate', 'upload'])('passes an internal IPA to the requested %s stage', (stage) => {
    const result = runStage(stage, 'fun.yunle.apps', true)
    expect(result.status, result.stderr).toBe(0)
    expect(result.calls).toContain(`altool --${stage}-app`)
  })
})
