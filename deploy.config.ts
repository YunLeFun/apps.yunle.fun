import process from 'node:process'
import { defineConfig } from '@yunlefun/deploy'

import consola from 'consola'

export default defineConfig({
  type: 'tencent-scf',

  docker: {
    // 10s 检查一次
    interval: 10000,
  },

  tencent: {
    client: {
      region: 'ap-guangzhou',
      credential: {
        secretId: process.env.TENCENT_CLOUD_SECRET_ID,
        secretKey: process.env.TENCENT_CLOUD_SECRET_KEY,
      },
    },
    scf: {
      alias: {
        name: '$DEFAULT',
      },
      function: {
        Namespace: 'YunLeFun',
        FunctionName: 'yunle-fun',
      },
      ImageConfig: {
        ImageType: 'personal',
        ContainerImageAccelerate: false,
      },
    },
    tcr: {
      region: 'ap-guangzhou',
      token: process.env.TENCENT_CLOUD_TCR_TOKEN,
      image: {
        RepoName: 'yunlefun/yunle-fun',
      },
    },
  },

  notification: {
    feishu: {
      enable: true,
    },
  },

  onDeployed: async () => {
    consola.success('部署完成')
  },
})
