declare let Wechat: {
  auth: (scope: string, state: string, succes: (res: any) => void, fail: (res: any) => void) => void
}
