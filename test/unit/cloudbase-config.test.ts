import { describe, expect, it } from 'vitest'
import { DEFAULT_CLOUDBASE_ENV_ID } from '../../app/constants/cloudbase'
import { resolveCloudbaseAdminInitConfig, resolveCloudbaseEnvId } from '../../server/utils/cloudbase-config'

describe('cloudbase config', () => {
  it('uses server runtime config before public config and environment variables', () => {
    expect(resolveCloudbaseEnvId({
      tcbEnvId: 'server-env',
      public: { tcbEnvId: 'public-env' },
    }, {
      NUXT_PUBLIC_TCB_ENV_ID: 'process-env',
    })).toBe('server-env')
  })

  it('uses public runtime config when server config is empty', () => {
    expect(resolveCloudbaseEnvId({
      tcbEnvId: '',
      public: { tcbEnvId: 'public-env' },
    }, {
      NUXT_PUBLIC_TCB_ENV_ID: 'process-env',
    })).toBe('public-env')
  })

  it('supports deployment environment variable aliases', () => {
    expect(resolveCloudbaseEnvId({
      public: { tcbEnvId: '' },
    }, {
      TCB_ENV_ID: 'tcb-env',
    })).toBe('tcb-env')

    expect(resolveCloudbaseEnvId({
      public: { tcbEnvId: '' },
    }, {
      CLOUDBASE_ENV_ID: 'cloudbase-env',
    })).toBe('cloudbase-env')
  })

  it('falls back to the production CloudBase environment id', () => {
    expect(resolveCloudbaseEnvId({
      tcbEnvId: '',
      public: { tcbEnvId: '' },
    }, {})).toBe(DEFAULT_CLOUDBASE_ENV_ID)
  })

  it('builds admin init config without forcing explicit secrets', () => {
    expect(resolveCloudbaseAdminInitConfig({
      public: { tcbEnvId: '' },
    }, {})).toEqual({
      env: DEFAULT_CLOUDBASE_ENV_ID,
    })
  })

  it('passes admin secrets only when they are configured as a pair', () => {
    expect(resolveCloudbaseAdminInitConfig({
      tcbEnvId: 'server-env',
      tencentApiSecretId: 'secret-id',
      tencentApiSecretKey: 'secret-key',
    }, {})).toEqual({
      env: 'server-env',
      secretId: 'secret-id',
      secretKey: 'secret-key',
    })

    expect(resolveCloudbaseAdminInitConfig({
      tcbEnvId: 'server-env',
      tencentApiSecretId: 'secret-id',
      tencentApiSecretKey: '',
    }, {})).toEqual({
      env: 'server-env',
    })
  })
})
