# 草案：原生 `window.ylf.getCloudbaseSession`（可选优化）

> 状态：**Swift 草案，未编译/未测**。需在 Xcode 构建 + 真机/模拟器验证后再合入。
> 作者非 iOS 环境产出，仅照 `requestAuthCode` 模式镜像，键名/错误处理请按实际微调。

## 这是什么 / 为什么可选

`@yunlefun/sso` 的原生适配器 `requestSsoNative` 取会话时**优先**调 `window.ylf.getCloudbaseSession`，
没有才回退 `getAuthCode` + 页面向 `/api/jsapi/auth/exchange` 兑换。

- **回退路径现在就能用**：`server/middleware/cors.ts` 已对 `/api/jsapi/auth/` 按 `jsapiAuthAllowedOrigins`
  放行跨源子应用，子应用页面的兑换 fetch 不会被 CORS 拦。所以本草案**不是必需**。
- **本草案的收益**：让**原生**完成「mint code → exchange」两步，直接把会话交给页面——
  页面零跨域请求、少一次 RTT、对 `apiBaseUrl`（含 `NATIVE_API_BASE_URL` 打包态）天然一致。

## 三处改动（`ios/App/App/WebViewController.swift`）

### 1) 注入 JS（`setupJSBridge` 的 `window.ylf` 字面量里，`getAuthCode` 之后加一行）

```text
getCloudbaseSession: function (options) { return invoke('getCloudbaseSession', options || {}) },
```

### 2) 方法注册表（`jsapiRegistry` 里登记，与 `getAuthCode` 同为 `.trusted`）

```swift
"getCloudbaseSession": .trusted,
```

### 3) 分发 + 实现（`handleJSAPI` 加 case，并新增 `requestCloudbaseSession`）

```swift
// handleJSAPI 的 switch 里：
case "getCloudbaseSession":
    requestCloudbaseSession(params: params, origin: origin, reply: reply)
```

```swift
/// 原生内部完成「mint 授权码 → 兑换会话」，直接把会话回给页面（页面零跨域）。
/// 镜像 requestAuthCode 的请求构造；两步串联，任一步失败即 reject。
private func requestCloudbaseSession(
    params: [String: Any],
    origin: WKSecurityOrigin,
    reply: @escaping (Any?, String?) -> Void
) {
    guard let auth = authContext,
          !auth.accessToken.isEmpty,
          !auth.apiBaseUrl.isEmpty,
          let base = URL(string: auth.apiBaseUrl)
    else {
        reply(nil, "login required")
        return
    }

    let scope = normalizeScope(params["scope"])

    // —— 通用 POST 小工具（Bearer 鉴权 + JSON）——
    func post(_ path: String, _ body: [String: Any], _ done: @escaping ([String: Any]?, String?) -> Void) {
        guard let url = URL(string: path, relativeTo: base) else {
            done(nil, "bad request: invalid endpoint")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        do { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        catch { done(nil, "bad request: invalid payload"); return }

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { done(nil, "request failed: \(error.localizedDescription)"); return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data = data else {
                done(nil, "request failed")
                return
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            done(json, json == nil ? "invalid response" : nil)
        }.resume()
    }

    func finish(_ result: Any?, _ message: String?) {
        DispatchQueue.main.async { reply(result, message) }
    }

    // 1) mint：同 requestAuthCode 的入参（cloudbase:session 作用域时带上宿主 session）
    var codeBody: [String: Any] = [
        "appId": appInfo?.id ?? "",
        "origin": originString(origin),
        "scope": scope,
    ]
    if scope.contains("cloudbase:session"), !auth.refreshToken.isEmpty {
        codeBody["session"] = ["access_token": auth.accessToken, "refresh_token": auth.refreshToken]
    }

    post("/api/jsapi/auth/code", codeBody) { mintRes, mintErr in
        if let mintErr = mintErr { finish(nil, mintErr); return }
        guard let code = mintRes?["code"] as? String, !code.isEmpty else {
            finish(nil, "mint failed: no code")
            return
        }
        // 2) exchange：换出页面自己的会话
        post("/api/jsapi/auth/exchange", ["code": code, "origin": self.originString(origin)]) { exRes, exErr in
            if let exErr = exErr { finish(nil, exErr); return }
            // exchange 返回 { data: { session: { access_token, refresh_token }, user } }
            guard let dataObj = exRes?["data"] as? [String: Any],
                  let session = dataObj["session"] as? [String: Any],
                  session["access_token"] is String, session["refresh_token"] is String
            else {
                finish(nil, "exchange failed")
                return
            }
            // 适配器读 { access_token, refresh_token }；user 一并带回便于页面展示
            var out = session
            if let user = dataObj["user"] { out["user"] = user }
            finish(out, nil)
        }
    }
}
```

## 验证 checklist（你来做）

- [ ] Xcode 编译通过（语法/可选解包/`self` 捕获）。
- [ ] 真机：授信域页面调 `signInWithSso(auth)` → 走 native → 无跨域请求即登录。
- [ ] 非授信域：`getCloudbaseSession` 不应放行（`isTrustedOrigin` 已统一拦截）。
- [ ] 失败回退：原生异常时适配器仍会落到 `getAuthCode` 路径（页面侧）。

> 合入后即可删掉对 `/api/jsapi/auth/exchange` 的跨源依赖（CORS 仍保留无妨）。在此之前，回退路径已可用。
