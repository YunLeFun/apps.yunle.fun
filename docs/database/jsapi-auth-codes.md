# jsapi_auth_codes 集合

云乐坊 App 内 JSAPI 登录授权码集合。该集合只由 Nitro 服务端写入和消费，
客户端安全规则应拒绝直接读写。

## 字段

| 字段         | 类型       | 说明                                                        |
| ------------ | ---------- | ----------------------------------------------------------- |
| `codeHash`   | `string`   | 授权码 SHA-256，永不保存明文 code                           |
| `uid`        | `string`   | CloudBase Auth 用户 ID                                      |
| `user`       | `object`   | 兑换时返回的最小用户快照                                    |
| `appId`      | `string`   | 发起 JSAPI 的应用 ID                                        |
| `origin`     | `string`   | 发起 JSAPI 的页面 origin                                    |
| `scope`      | `string[]` | 授权范围，默认 `profile`                                    |
| `session`    | `object`   | 可选，`cloudbase:session` scope 下的 CloudBase session 快照 |
| `createdAt`  | `number`   | 创建时间戳                                                  |
| `expiresAt`  | `number`   | 过期时间戳，默认 5 分钟                                     |
| `consumedAt` | `number`   | 兑换时间戳，`0` 表示未使用                                  |

## 约束

- code 只返回给授信 JSAPI 调用方，服务端仅保存 `codeHash`。
- 兑换接口要求请求 `Origin` 与记录里的 `origin` 完全一致。
- code 只能兑换一次，过期或已消费都返回 400。
- `session` 包含 `access_token` / `refresh_token`，只应由服务端写入并随 code TTL
  短期存在；客户端安全规则必须拒绝直接读写。
- 生产环境应定期清理 `expiresAt` 早于当前时间的记录。
