import Foundation
import Security
import UIKit

/// A code is accepted only through OpenSDK with the state of the current attempt.
@MainActor
final class WeChatAuthorization {
    struct Driver {
        // Checking the URL scheme does not initialize OpenSDK before consent.
        var isInstalled: @MainActor () -> Bool = {
            YunleWeChatBridge.isLinked() && UIApplication.shared.canOpenURL(URL(string: "weixin://")!)
        }
        var register: (String, String) -> Bool = { YunleWeChatBridge.prepare(appID: $0, universalLink: $1) }
        var send: (String, @escaping @Sendable (Bool) -> Void) -> Void = { YunleWeChatBridge.sendAuth(state: $0, completion: $1) }
        var handleURL: (URL, @escaping YunleWeChatResponse) -> Bool = { YunleWeChatBridge.handle(url: $0, response: $1) }
        var handleActivity: (NSUserActivity, @escaping YunleWeChatResponse) -> Bool = { YunleWeChatBridge.handle(activity: $0, response: $1) }
    }

    static let appID = "wx925d6e320d64f30a"
    static let universalLink = "https://apps.yunle.fun/auth/wechat/"
    static let shared = WeChatAuthorization()
    private let driver: Driver
    private var registered = false
    private var pending: (state: String, deadline: ContinuousClock.Instant, reply: CheckedContinuation<String, Error>)?
    private var timeout: Task<Void, Never>?

    init(driver: Driver? = nil) {
        self.driver = driver ?? Driver()
    }

    var isAvailable: Bool {
        driver.isInstalled()
    }

    private func prepare() -> Bool {
        guard isAvailable else { return false }
        if !registered {
            registered = driver.register(Self.appID, Self.universalLink)
        }
        return registered
    }

    func authorize() async throws -> String {
        guard pending == nil, prepare() else { throw AccountError.unavailable }
        let state = try Self.randomState()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { reply in
                pending = (state, .now.advanced(by: .seconds(180)), reply)
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(180)) } catch { return }
                    self?.finish(.failure(WeChatAccountError.authorizationFailed), state: state)
                }
                driver.send(state) { [weak self] sent in
                    guard !sent else { return }
                    Task { @MainActor in self?.finish(.failure(AccountError.unavailable), state: state) }
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError()), state: state) }
        }
    }

    func handle(_ url: URL) -> Bool {
        guard pending != nil else { return false }
        if Self.isWeChatLink(url) {
            let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
            activity.webpageURL = url
            return handle(activity)
        }
        guard url.scheme?.lowercased() == Self.appID else { return false }
        return driver.handleURL(url, response)
    }

    func handle(_ activity: NSUserActivity) -> Bool {
        guard pending != nil, activity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = activity.webpageURL, Self.isWeChatLink(url) else { return false }
        return driver.handleActivity(activity, response)
    }

    static func isWeChatLink(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "apps.yunle.fun" && url.port == nil
            && url.user == nil && url.password == nil
            && URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath.hasPrefix("/auth/wechat/") == true
    }

    private static func randomState() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AccountError.unavailable
        }
        return Data(bytes).map { String(format: "%02x", $0) }.joined()
    }

    private var response: YunleWeChatResponse {
        { [weak self] status, state, code in
            guard let state, !state.isEmpty else { return }
            Task { @MainActor in
                self?.finish(Result { try Self.validatedCode(status: status, code: code) }, state: state)
            }
        }
    }

    nonisolated static func validatedCode(status: Int, code: String?) throws -> String {
        if status == -2 || status == -4 { throw CancellationError() }
        guard status == 0, let code, (1...512).contains(code.utf8.count),
              code.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                  || (97...122).contains($0) || $0 == 45 || $0 == 95 })
        else { throw WeChatAccountError.authorizationFailed }
        return code
    }

    private func finish(_ result: Result<String, Error>, state: String) {
        guard let pending, pending.state == state else { return }
        self.pending = nil
        timeout?.cancel()
        timeout = nil
        pending.reply.resume(with: .now < pending.deadline ? result : .failure(WeChatAccountError.authorizationFailed))
    }
}
