export default defineEventHandler(() => {
  // 查询用户

  return {
    // 0 | 1 | 2
    // 成功
    // code: 0,
    // 手机端未确认
    code: 1,
    // 失败
    // code: 2,
    // 过期 后端设置为 5min 300s
    // code: -1,
  }
})
