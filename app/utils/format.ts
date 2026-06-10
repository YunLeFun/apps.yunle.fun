/** 会员到期日期展示，如 `2026/6/10 到期`（无到期时间返回空串） */
export function formatExpireDate(expireAt: number | null | undefined): string {
  if (!expireAt)
    return ''
  const d = new Date(expireAt)
  return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()} 到期`
}

/** 流水时间展示，如 `6/10 09:30` */
export function formatTxTime(ts: number): string {
  const d = new Date(ts)
  const pad = (n: number) => n.toString().padStart(2, '0')
  return `${d.getMonth() + 1}/${d.getDate()} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}
