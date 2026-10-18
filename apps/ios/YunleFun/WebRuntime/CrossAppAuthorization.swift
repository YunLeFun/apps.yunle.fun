import Foundation
import SwiftUI
import UIKit

// 跨 App 授权：其他 App 打开 https://www.yunle.fun/auth/app?…，云乐坊认领这个 Universal Link，
// 用当前账号显式确认后，把一次性 code 回跳到接入方在注册表中登记的 HTTPS 回调。
// 设计见 docs/dev/ios-cross-app-authorization.md。

/// 跨 App 请求只包含协议事实。来源 App 无法证明，结果的去向由注册表与接入方的 Universal Link 归属限定。
struct CrossAppAuthorizationRequest: Equatable {
    let clientID: String
    let redirectURI: URL
    let nonce: String
    let codeChallenge: String

    /// 回调地址的 origin，交给 `HostSsoRequest` 与注册策略核对
    var sourceOrigin: String { "https://\(redirectURI.host ?? "")" }

    /// 不转发接入方的 `prompt`：跨 App 总是显式确认，"使用其他账号"由面板提供
    var brokerParameters: [String: Any] {
        ["clientId": clientID, "redirectUri": redirectURI.absoluteString, "nonce": nonce,
         "codeChallenge": codeChallenge, "codeChallengeMethod": "S256", "scope": ["identity:bootstrap"]]
    }
}

enum CrossAppAuthorizationLink {
    static let host = "www.yunle.fun"
    static let path = "/auth/app"
    private static let required: Set = ["client_id", "redirect_uri", "scope", "nonce", "code_challenge", "code_challenge_method"]
    private static let optional: Set = ["prompt"]

    /// 地址落在授权入口上即由本解析器负责，无效时提示而不是交给其他路由
    static func isEntry(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == host && url.path == path
    }

    /// 每个参数恰好出现一次；不接受额外参数、fragment、userinfo、端口、`native_callback_uri` 或 `prompt=none`
    static func parse(_ url: URL) -> CrossAppAuthorizationRequest? {
        guard url.absoluteString.utf8.count <= 4096,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == host, parts.percentEncodedPath == path,
              parts.port == nil, parts.user == nil, parts.password == nil, parts.fragment == nil,
              let items = parts.queryItems else { return nil }
        var values: [String: String] = [:]
        for item in items {
            guard required.contains(item.name) || optional.contains(item.name),
                  values[item.name] == nil, let value = item.value, !value.isEmpty else { return nil }
            values[item.name] = value
        }
        guard required.isSubset(of: values.keys),
              let client = values["client_id"], HostSsoRequest.matches(client, "^[a-z0-9][a-z0-9-]{1,127}$"),
              let redirect = values["redirect_uri"].flatMap(HostSsoRequest.httpsURL), redirect.port == nil,
              values["scope"] == "identity:bootstrap", values["code_challenge_method"] == "S256",
              let nonce = values["nonce"], HostSsoRequest.matches(nonce, "^[A-Za-z0-9_-]{32,128}$"),
              let challenge = values["code_challenge"], HostSsoRequest.matches(challenge, "^[A-Za-z0-9_-]{43}$"),
              values["prompt"].map({ ["select_account", "consent"].contains($0) }) ?? true
        else { return nil }
        return CrossAppAuthorizationRequest(clientID: client, redirectURI: redirect, nonce: nonce, codeChallenge: challenge)
    }
}

/// 回跳结果，与 `@yunlefun/sso` 的 `encodeSsoRedirectResult` 逐字节兼容（键序 nonce、iss、ok、code / reason）。
enum CrossAppRedirect: Equatable {
    case approved(code: String)
    case denied
    case accountSelectionRequired

    func callbackURL(for request: CrossAppAuthorizationRequest) -> URL? {
        // nonce 与 code 已按 base64url 校验，issuer 和 reason 为常量，无需 JSON 转义
        let head = #"{"nonce":"\#(request.nonce)","iss":"\#(HostSsoPolicy.issuer)","ok":"#
        let body: String
        switch self {
        case .approved(let code):
            guard HostSsoRequest.matches(code, "^[A-Za-z0-9_-]{43}$") else { return nil }
            body = head + #"true,"code":"\#(code)"}"#
        case .denied:
            body = head + #"false,"reason":"access_denied"}"#
        case .accountSelectionRequired:
            body = head + #"false,"reason":"account_selection_required"}"#
        }
        let encoded = Data(body.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "\(request.redirectURI.absoluteString)#ylf_sso=\(encoded)")
    }
}

enum CrossAppAuthorizationIssue: Equatable {
    case invalidRequest, busy, unableToReturn(String)

    var runtimeIssue: RuntimeIssue {
        switch self {
        case .invalidRequest: RuntimeIssue(title: "该授权请求无效", message: "请回到发起登录的 App 重新尝试。")
        case .busy: RuntimeIssue(title: "有一个授权正在进行", message: "请先完成或取消当前的授权，再回到发起登录的 App 重试。")
        case .unableToReturn(let name): RuntimeIssue(title: "无法返回\(name)", message: "请更新\(name)后重试。本次授权已作废。")
        }
    }
}

/// 把 `NativeAuthorizationBroker` 的一次决策接到跨 App 场景：面板弹在当前最上层，不切换 Tab；
/// 结果只通过 `universalLinksOnly` 回跳，打不开就丢弃 code，绝不在 Safari 中打开。
@MainActor
final class CrossAppAuthorizationPage: HostAuthorizationPage {
    typealias Opener = (URL, @escaping @MainActor (Bool) -> Void) -> Void

    let requestID = UUID().uuidString
    let request: CrossAppAuthorizationRequest
    private weak var accounts: AccountStore?
    private let presenter: () -> UIViewController?
    private let open: Opener
    private let finished: (CrossAppAuthorizationIssue?) -> Void
    private var isResolved = false
    private var applicationName = "原 App"
    private weak var modal: UIViewController?

    init(request: CrossAppAuthorizationRequest, accounts: AccountStore?,
         presenter: @escaping () -> UIViewController? = CrossAppAuthorizationPage.topPresenter,
         open: @escaping Opener = CrossAppAuthorizationPage.openUniversalLink,
         finished: @escaping (CrossAppAuthorizationIssue?) -> Void) {
        self.request = request; self.accounts = accounts
        self.presenter = presenter; self.open = open; self.finished = finished
    }

    func isPending(_ requestID: String) -> Bool { !isResolved && requestID == self.requestID }
    // 跨 App 请求没有网页侧的超时，由 broker 的决策超时兜底
    func pause(_ requestID: String) -> Bool { isPending(requestID) }
    func resume(_ requestID: String) -> Bool { isPending(requestID) }

    func resolve(_ requestID: String, result: [String: Any]?, error: String?) {
        guard isPending(requestID) else { return }
        isResolved = true
        if let code = result?["code"] as? String {
            returnToClient(.approved(code: code))
        } else if error == HostAuthorizationError.invalidRequest.code {
            // 参数或注册策略不通过时不回跳，避免把云乐坊当作向任意链接发送内容的跳板
            finished(.invalidRequest)
        } else {
            // 拒绝、关闭面板、超时与账号变化都按拒绝返回，不携带 code
            returnToClient(.denied)
        }
    }

    func useOtherAccount(_ requestID: String) -> Bool {
        guard isPending(requestID) else { return false }
        isResolved = true
        // v1 不在云乐坊内切换账号，交给接入方用网页授权选择其他账号
        returnToClient(.accountSelectionRequired)
        return true
    }

    func showLogin(application: String, completion: @escaping (Bool) -> Void) -> Bool {
        guard let presenter = presenter(), let accounts else { return false }
        applicationName = application
        let controller = HostLoginController(accounts: accounts, application: application) { [weak self] result in
            self?.modal = nil
            completion(result)
        }
        modal = controller
        presenter.present(controller, animated: true)
        return true
    }

    func showConsent(policy: HostSsoPolicy, user: AccountUser,
                     completion: @escaping (AuthorizationSheetChoice) -> Void) -> Bool {
        guard let presenter = presenter() else { return false }
        applicationName = policy.applicationName
        let controller = AuthorizationConsentViewController(content: AuthorizationSheetContent(
            applicationName: policy.applicationName, applicationOrigin: policy.applicationOrigin,
            applicationIconURL: policy.applicationIconURL, accountName: user.displayName,
            accountAvatarURL: user.picture, permissionDescription: policy.permissionDescription,
            authorizationNotice: "来自另一个 App 的登录请求"
        )) { [weak self] choice in
            self?.modal = nil
            completion(choice)
        }
        if let presentation = controller.sheetPresentationController {
            configureAuthorizationConsentPresentation(presentation,
                                                       contentSizeCategory: presenter.traitCollection.preferredContentSizeCategory)
        }
        modal = controller
        presenter.present(controller, animated: true)
        return true
    }

    func dismissAuthorizationUI() {
        if let consent = modal as? AuthorizationConsentViewController { consent.expire() }
        else { modal?.dismiss(animated: false) }
        modal = nil
    }

    private func returnToClient(_ outcome: CrossAppRedirect) {
        let name = applicationName
        guard let url = outcome.callbackURL(for: request) else {
            finished(.unableToReturn(name)); return
        }
        open(url) { [finished] opened in finished(opened ? nil : .unableToReturn(name)) }
    }

    static func openUniversalLink(_ url: URL, completion: @escaping @MainActor (Bool) -> Void) {
        UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { opened in
            Task { @MainActor in completion(opened) }
        }
    }

    static func topPresenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        guard let top, !top.isBeingPresented, !top.isBeingDismissed else { return nil }
        return top
    }
}

/// 接住授权入口的 Universal Link。冷启动时等账号恢复完成再开始，避免误判为未登录。
@MainActor
final class CrossAppAuthorizationCoordinator: ObservableObject {
    @Published var issue: RuntimeIssue?
    private var page: CrossAppAuthorizationPage?

    /// 返回 `true` 表示地址属于授权入口（无论是否有效），调用方不再交给其他路由
    func handle(_ url: URL, runtime: NativeWebRuntime, accounts: AccountStore) -> Bool {
        guard CrossAppAuthorizationLink.isEntry(url) else { return false }
        guard let request = CrossAppAuthorizationLink.parse(url) else {
            issue = CrossAppAuthorizationIssue.invalidRequest.runtimeIssue
            return true
        }
        guard page == nil, !runtime.isAuthorizationBusy else {
            issue = CrossAppAuthorizationIssue.busy.runtimeIssue
            return true
        }
        let page = CrossAppAuthorizationPage(request: request, accounts: accounts) { [weak self] issue in
            self?.page = nil
            if let issue { self?.issue = issue.runtimeIssue }
        }
        self.page = page
        Task { [weak runtime, weak accounts] in
            for _ in 0..<100 where accounts?.isRestoring == true {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let runtime, page.isPending(page.requestID) else { return }
            runtime.beginCrossAppAuthorization(page)
        }
        return true
    }
}
