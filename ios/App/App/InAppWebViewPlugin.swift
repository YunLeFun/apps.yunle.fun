import Capacitor
import Foundation
import UIKit
import WebKit

@objc(InAppWebViewPlugin)
public class InAppWebViewPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "InAppWebViewPlugin"
    public let jsName = "InAppWebView"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "open", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "close", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "updateAppInfo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "listSessions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "endSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "resolveAuthorization", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clearIdentitySessions", returnType: CAPPluginReturnPromise),
    ]

    /// 后台会话池（强持有，保活已最小化/暂停的 WebView）。
    /// LRU 顺序：index 0 = 最近交互；超过上限淘汰最旧的暂停会话。
    /// 「最小化」「跳详情页」只暂停（dismiss 保留状态），「结束」才真正移除释放。
    private var sessions: [WebViewController] = []
    private let maxSessions = 3

    /// 会话去重 / 定位键：优先 appId，无则用 URL（与 WebViewController.sessionKey 一致）
    private func indexOfSession(key: String) -> Int? {
        sessions.firstIndex { $0.sessionKey == key }
    }

    /// 移到 LRU 最前（最近交互）
    private func moveToFront(_ vc: WebViewController) {
        if let i = sessions.firstIndex(where: { $0 === vc }) {
            sessions.remove(at: i)
        }
        sessions.insert(vc, at: 0)
    }

    private func removeSession(_ vc: WebViewController) {
        vc.cancelPendingAuthorizations()
        if let i = sessions.firstIndex(where: { $0 === vc }) {
            sessions.remove(at: i)
        }
    }

    /// 超出上限时从最旧端淘汰一个未在前台的会话（其 WKWebView 随之释放）
    private func evictIfNeeded() {
        while sessions.count > maxSessions {
            guard let idx = sessions.lastIndex(where: { $0.presentingViewController == nil }) else { break }
            removeSession(sessions[idx])
        }
    }

    /// 把当前后台会话列表推给 JS（悬浮球 / 托盘 / 主屏「正在运行」区据此渲染）
    private func notifySessionsChanged() {
        notifyListeners("sessionsChanged", data: ["sessions": sessions.map { $0.sessionInfo() }])
    }

    @objc func open(_ call: CAPPluginCall) {
        guard let urlString = call.getString("url"),
              let url = URL(string: urlString)
        else {
            call.reject("Missing or invalid url")
            return
        }

        let title = call.getString("title") ?? ""
        let toolbarColor = call.getString("toolbarColor")
        let appInfo = parseAppInfo(call.getObject("app"))
        // 展示形态：titlebar（默认）= 顶部固定标题栏 + 单菜单按钮；immersive = 全屏平铺 + 悬浮胶囊（官方应用声明专属）
        let displayMode = WebViewDisplayMode(rawValue: call.getString("displayMode") ?? "") ?? .titlebar
        // 跨站外链打开方式：safari-view（默认）= App 内系统浏览器视图；default-browser = 跳出到手机默认浏览器
        let externalLinkBehavior = ExternalLinkBehavior(rawValue: call.getString("externalLinkMode") ?? "") ?? .safariView
        // 本次会话追加的 JSAPI 授信域（敏感能力鉴权用，详见 WebViewController.isTrustedOrigin）
        let trustedHosts = call.getArray("trustedHosts", String.self) ?? []

        // 会话键：优先 appId，无则用 URL（与 WebViewController.sessionKey 一致）
        let sessionKey = (appInfo?.id).flatMap { $0.isEmpty ? nil : $0 } ?? urlString

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 命中暂停中的同会话（且展示形态一致）：直接恢复，保留页面状态、刷新可变上下文
            if let idx = self.indexOfSession(key: sessionKey),
               self.sessions[idx].presentingViewController == nil,
               self.sessions[idx].displayMode == displayMode {
                let paused = self.sessions[idx]
                paused.externalLinkBehavior = externalLinkBehavior
                paused.extraTrustedHosts = trustedHosts
                self.moveToFront(paused)
                self.bridge?.viewController?.present(paused, animated: true) {
                    call.resolve()
                }
                self.notifySessionsChanged()
                return
            }

            // 同键但形态不一致（无法复用）：释放旧的，走新建
            if let idx = self.indexOfSession(key: sessionKey) {
                self.removeSession(self.sessions[idx])
            }

            let vc = WebViewController()
            vc.url = url
            vc.customTitle = title
            vc.toolbarColorHex = toolbarColor
            vc.appInfo = appInfo
            vc.displayMode = displayMode
            vc.externalLinkBehavior = externalLinkBehavior
            vc.extraTrustedHosts = trustedHosts
            vc.onClose = { [weak self, weak vc] in
                guard let self = self, let vc = vc else { return }
                self.removeSession(vc)
                self.notifyListeners("browserFinished", data: [:])
                self.notifySessionsChanged()
            }
            vc.onMinimize = { [weak self, weak vc] in
                // 压后台：保活会话、移到最前；通知前台收起 + 最小化事件（区分于「结束」）+ 刷新后台列表
                guard let self = self, let vc = vc else { return }
                self.moveToFront(vc)
                self.notifyListeners("browserFinished", data: [:])
                self.notifyListeners("browserMinimized", data: ["name": vc.appInfo?.name ?? ""])
                self.notifySessionsChanged()
            }
            vc.onDetail = { [weak self] appId in
                self?.notifyListeners("detailRequested", data: ["appId": appId])
            }
            vc.onAuthorizationRequest = { [weak self, weak vc] requestId, sourceOrigin, request in
                guard let self = self, let vc = vc else { return }
                self.notifyListeners("authorizationRequested", data: [
                    "requestId": requestId,
                    "sourceOrigin": sourceOrigin,
                    "appId": vc.appInfo?.id ?? "",
                    "request": request,
                ])
            }

            vc.modalPresentationStyle = .fullScreen
            self.sessions.insert(vc, at: 0)
            self.evictIfNeeded()

            self.bridge?.viewController?.present(vc, animated: true) {
                call.resolve()
            }
            self.notifySessionsChanged()
        }
    }

    @objc func close(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { call.resolve(); return }
            // 关闭当前前台会话（无前台则取最近一个）
            guard let vc = self.sessions.first(where: { $0.presentingViewController != nil }) ?? self.sessions.first else {
                call.resolve()
                return
            }
            if vc.presentingViewController != nil {
                vc.dismiss(animated: true) {
                    self.removeSession(vc)
                    self.notifyListeners("browserFinished", data: [:])
                    self.notifySessionsChanged()
                    call.resolve()
                }
            }
            else {
                self.removeSession(vc)
                self.notifyListeners("browserFinished", data: [:])
                self.notifySessionsChanged()
                call.resolve()
            }
        }
    }

    /// 打开后由 JS 异步补充应用元信息（如评价数），下次打开详情面板时生效
    @objc func updateAppInfo(_ call: CAPPluginCall) {
        guard let obj = call.getObject("app") else {
            call.resolve()
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let vc = self.sessions.first(where: { $0.presentingViewController != nil }) ?? self.sessions.first
            else {
                call.resolve()
                return
            }
            var info = vc.appInfo ?? WebAppInfo()
            Self.apply(obj, to: &info)
            vc.appInfo = info
            call.resolve()
        }
    }

    /// 返回当前后台会话列表（供悬浮球 / 托盘 / 主屏「正在运行」区渲染）
    @objc func listSessions(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            call.resolve(["sessions": self?.sessions.map { $0.sessionInfo() } ?? []])
        }
    }

    /// 彻底结束并释放指定会话（按 sessionKey）；前台会话则先收起
    @objc func endSession(_ call: CAPPluginCall) {
        let key = call.getString("id") ?? call.getString("key") ?? ""
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let idx = self.indexOfSession(key: key) else {
                call.resolve()
                return
            }
            let vc = self.sessions[idx]
            if vc.presentingViewController != nil {
                vc.dismiss(animated: true) {
                    self.removeSession(vc)
                    self.notifySessionsChanged()
                    call.resolve()
                }
                return
            }
            self.removeSession(vc)
            self.notifySessionsChanged()
            call.resolve()
        }
    }

    /// 把宿主 JS 签发的一次性授权码回传给发起请求的 WebView Promise。
    @objc func resolveAuthorization(_ call: CAPPluginCall) {
        guard let requestId = call.getString("requestId"), !requestId.isEmpty else {
            call.reject("Missing requestId")
            return
        }
        let result = call.getObject("result")
        let error = call.getString("error")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                call.reject("Browser unavailable")
                return
            }
            let resolved = self.sessions.contains {
                $0.resolveAuthorization(
                    requestId: requestId,
                    result: result,
                    error: error)
            }
            if resolved {
                call.resolve()
            }
            else {
                call.reject("Unknown or expired authorization request")
            }
        }
    }

    /// Apps 退出或切换账号后清除 Play 的 HttpOnly BFF cookie，并通知保活页面刷新身份。
    @objc func clearIdentitySessions(_ call: CAPPluginCall) {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        cookieStore.getAllCookies { [weak self] cookies in
            let playCookies = cookies.filter {
                $0.name == "__Host-ylf_play_session"
                    && $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                        .lowercased() == "play.yunle.fun"
            }
            let group = DispatchGroup()
            playCookies.forEach { cookie in
                group.enter()
                cookieStore.delete(cookie) {
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self?.sessions
                    .filter { ($0.url?.host ?? "").lowercased() == "play.yunle.fun" }
                    .forEach { $0.notifyHostIdentityChanged() }
                call.resolve()
            }
        }
    }

    private func parseAppInfo(_ obj: JSObject?) -> WebAppInfo? {
        guard let obj = obj else { return nil }
        var info = WebAppInfo()
        Self.apply(obj, to: &info)
        return info
    }

    /// 仅覆盖 JS 侧传入的字段（部分更新）
    private static func apply(_ obj: JSObject, to info: inout WebAppInfo) {
        if let v = obj["id"] as? String { info.id = v }
        if let v = obj["slug"] as? String { info.slug = v }
        if let v = obj["name"] as? String { info.name = v }
        if let v = obj["emoji"] as? String { info.emoji = v }
        if let v = obj["logo"] as? String { info.logo = v }
        if let v = obj["themeColor"] as? String { info.themeColor = v }
        if let v = obj["description"] as? String { info.description = v }
        if let v = obj["category"] as? String { info.category = v }
        if let v = obj["downloads"] as? String { info.downloads = v }
        if let v = obj["rating"] as? Double { info.rating = v }
        else if let v = obj["rating"] as? Int { info.rating = Double(v) }
        if let v = obj["ratingCount"] as? Int { info.ratingCount = v }
        else if let v = obj["ratingCount"] as? Double { info.ratingCount = Int(v) }
    }
}
