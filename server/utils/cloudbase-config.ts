import type { ICloudBaseConfig } from '@cloudbase/node-sdk'
import process from 'node:process'
import { DEFAULT_CLOUDBASE_ENV_ID } from '~/constants/cloudbase'

interface CloudbaseConfigLike {
  tcbEnvId?: unknown
  cloudbaseEnvId?: unknown
  tencentApiSecretId?: unknown
  tencentApiSecretKey?: unknown
  public?: {
    tcbEnvId?: unknown
    cloudbaseEnvId?: unknown
  }
}

type CloudbaseEnvLike = Record<string, string | undefined>

export function resolveCloudbaseEnvId(
  config: CloudbaseConfigLike,
  env: CloudbaseEnvLike = process.env,
): string {
  return firstNonEmptyString(
    config.tcbEnvId,
    config.cloudbaseEnvId,
    config.public?.tcbEnvId,
    config.public?.cloudbaseEnvId,
    env.NUXT_TCB_ENV_ID,
    env.NUXT_PUBLIC_TCB_ENV_ID,
    env.TCB_ENV_ID,
    env.CLOUDBASE_ENV_ID,
    env.CLOUDBASE_ENV,
  ) || DEFAULT_CLOUDBASE_ENV_ID
}

export function resolveCloudbaseAdminInitConfig(
  config: CloudbaseConfigLike,
  env: CloudbaseEnvLike = process.env,
): ICloudBaseConfig {
  const initConfig: ICloudBaseConfig = {
    env: resolveCloudbaseEnvId(config, env),
  }
  const secretId = stringOrNull(config.tencentApiSecretId)
  const secretKey = stringOrNull(config.tencentApiSecretKey)
  if (secretId && secretKey) {
    initConfig.secretId = secretId
    initConfig.secretKey = secretKey
  }
  return initConfig
}

function firstNonEmptyString(...values: unknown[]): string | null {
  for (const value of values) {
    const trimmed = stringOrNull(value)
    if (trimmed)
      return trimmed
  }
  return null
}

function stringOrNull(value: unknown): string | null {
  if (typeof value !== 'string')
    return null
  const trimmed = value.trim()
  return trimmed || null
}
