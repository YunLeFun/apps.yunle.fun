import CryptoKit
import Foundation
import Security
import SwiftUI
import WebKit
import XCTest
@testable import YunleFun

/// Explicit live contract validation with an existing managed synthetic identity.
/// The host token only reaches the fixed CloudBase gateway. The consumer receives
/// the one-time code and its own PKCE verifier, never the host session.
@MainActor
final class HostAuthorizationLiveTests: XCTestCase {
    private var observations: [[String: Any]] = []
    func testRealCloudApplicationLoginConsentAndSignOut() async throws {
        guard ProcessInfo.processInfo.environment["YUNLEFUN_LIVE_HOST_SSO_UI"] == "1" else {
            throw XCTSkip("Requires explicit live UI driving of the managed native login and consent")
        }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let input = cache.appendingPathComponent("iOSNativeValidation/host-sso-ui-accounts.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: input.path)
        guard let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0 else {
            return XCTFail("Live credentials require owner-only access")
        }
        let secret = try Data(contentsOf: input); try FileManager.default.removeItem(at: input)
        let pool = try JSONDecoder().decode(Pool.self, from: secret)
        guard pool.accounts.count == 1, let credential = pool.accounts.first,
              credential.id == "production-zero-balance", credential.environment == "production",
              credential.username == "ylf_prod_zero" else { return XCTFail("Requires the fixed zero-balance identity") }
        let service = "fun.yunle.apps.host-sso-ui." + UUID().uuidString
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary) }
        let directory = cache.appendingPathComponent("HostSSOUI-" + UUID().uuidString)
        let library = HomeLibrary(directory: directory)
        let catalog = CatalogStore()
        let runtime = NativeWebRuntime()
        let accounts = AccountStore(session: AccountSession(vault: KeychainAccountVault(service: service))) { id in
            runtime.resetIdentity(to: id); library.activateAccount(id); library.setAutoSyncEnabled(false)
        }
        runtime.configureAuthorization(accounts: accounts)
        let wallet = WalletStore(accounts: accounts)
        let purchases = PurchaseCoordinator(accounts: accounts, wallet: wallet)
        runtime.configureCommerce(wallet: wallet, purchases: purchases)
        let sync = HomeSyncCoordinator(accounts: accounts, library: library, monitorNetwork: false)
        let assistant = AssistantStore(accounts: accounts)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        let previous = window.rootViewController
        let page = UIHostingController(rootView: AppRootView().environmentObject(catalog).environmentObject(library)
            .environmentObject(runtime).environmentObject(accounts).environmentObject(wallet).environmentObject(purchases)
            .environmentObject(sync).environmentObject(assistant))
        window.rootViewController = page; window.makeKeyAndVisible()
        defer {
            runtime.resetIdentity()
            window.rootViewController = previous; window.makeKeyAndVisible()
            try? FileManager.default.removeItem(at: directory)
        }
        var failure: Error?
        var appSignedIn = false
        var appSignedOut = false
        var consentSeen = false
        var hostSignedOut = false
        do {
            await catalog.load()
            let app = try XCTUnwrap(catalog.applications.first { $0.marketShortName == "ai-sfc" })
            try await Task.sleep(nanoseconds: 500_000_000)
            runtime.open(app, catalog: catalog, library: library)
            print("YLF_UI_HOST_SSO_READY")
            let deadline = Date().addingTimeInterval(300)
            while Date() < deadline {
                if let browser = presentedBrowser(in: window) {
                    if browser.presentedViewController is AuthorizationConsentViewController { consentSeen = true }
                    if let web = webView(in: browser.view),
                       let body = try? await web.evaluateJavaScript("document.body.innerText") as? String,
                       let user = accounts.user, user.username == credential.username, user.isUsable,
                       body.contains(user.displayName), browser.presentedViewController == nil {
                        appSignedIn = true; break
                    }
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            guard appSignedIn, consentSeen else { throw LiveFailure.identity }
            attach(window, name: "real-cloud-app-native-sso-signed-in")
            print("YLF_UI_CLOUD_IDENTITY_READY")
            let logoutDeadline = Date().addingTimeInterval(90)
            while Date() < logoutDeadline {
                if let browser = presentedBrowser(in: window),
                   let web = webView(in: browser.view),
                   let user = accounts.user,
                   let body = try? await web.evaluateJavaScript("document.body.innerText") as? String,
                   !body.contains(user.displayName), body.contains("登录") {
                    appSignedOut = true; break
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            guard appSignedOut else { throw LiveFailure.identity }
            attach(window, name: "real-cloud-app-signed-out")
        } catch { failure = error }
        for user in accounts.overview.users {
            do { try await accounts.remove(user.id); hostSignedOut = accounts.notice == nil }
            catch { if failure == nil { failure = error } }
        }
        let report: [String: Any] = ["account": credential.id, "nativeConsentSeen": consentSeen,
            "applicationDisplayedHostIdentity": appSignedIn, "applicationSignedOut": appSignedOut,
            "hostSignedOut": hostSignedOut, "hostCredentialsInjectedIntoWebView": false,
            "scope": "one simulator and AI Spring Festival couplets production application"]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "native-host-sso-ui-live"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertNil(failure.map { _ in "Live UI authorization journey failed; response contents omitted" })
        XCTAssertTrue(appSignedIn); XCTAssertTrue(appSignedOut); XCTAssertTrue(consentSeen); XCTAssertTrue(hostSignedOut)
    }
    private func presentedBrowser(in window: UIWindow) -> WebViewController? {
        let presented = window.rootViewController?.presentedViewController
        if let navigation = presented as? UINavigationController {
            return navigation.viewControllers.compactMap { $0 as? WebViewController }.first
        }
        return presented as? WebViewController
    }
    private func webView(in view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        for child in view.subviews { if let web = webView(in: child) { return web } }
        return nil
    }
    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testNativeCodeExchangePKCEReplayAndIdentity() async throws {
        guard ProcessInfo.processInfo.environment["YUNLEFUN_LIVE_HOST_SSO"] == "1" else {
            throw XCTSkip("Requires managed synthetic credentials and explicit live SSO validation")
        }
        let input = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iOSNativeValidation/host-sso-accounts.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: input.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber, permissions.intValue & 0o077 == 0 else {
            return XCTFail("Live credentials require owner-only file access")
        }
        let data = try Data(contentsOf: input)
        try FileManager.default.removeItem(at: input)
        let pool = try JSONDecoder().decode(Pool.self, from: data)
        guard pool.accounts.count == 1, let credential = pool.accounts.first,
              credential.id == "production-zero-balance", credential.environment == "production",
              credential.username == "ylf_prod_zero", !credential.password.isEmpty else {
            return XCTFail("Only the approved zero-balance synthetic identity may run this test")
        }
        let keychainService = "fun.yunle.apps.host-sso-live." + UUID().uuidString
        let accounts = AccountStore(session: AccountSession(vault: KeychainAccountVault(service: keychainService)))
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                              kSecAttrService as String: keychainService] as CFDictionary) }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.httpCookieAcceptPolicy = .never
        config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
        let consumer = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
        defer { consumer.invalidateAndCancel() }
        let deviceID = UUID().uuidString
        var temporaryToken: String?
        var stages: [String] = []
        var stage = "host login"
        var failure: Error?
        var temporarySignedOut = false
        var hostSignedOut = false
        do {
            try await accounts.passwordSignIn(identifier: credential.username, password: credential.password, captcha: nil)
            let identity = try await accounts.authorization(forceRefresh: true)
            let verifier = randomValue()
            let nonce = randomValue()
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            let origin = "https://ai-sfc.yunle.fun"
            let request = try HostSsoRequest(sourceOrigin: origin, parameters: [
                "clientId": "ai-sfc-web", "redirectUri": origin + "/", "scope": ["identity:bootstrap"],
                "nonce": nonce, "codeChallenge": challenge, "codeChallengeMethod": "S256", "prompt": "consent",
            ])
            let host = HostAuthorizationService()
            stage = "registered policy"
            let policy = try await host.resolve(request)
            guard policy.applicationID == "ai-sfc", policy.applicationOrigin == origin,
                  policy.prompt == "consent" else { throw LiveFailure.protocolResponse }
            stages.append("native resolver validates registered AI Spring Festival couplets policy")
            stage = "native code issuance"
            let issued = try await host.issue(request, identity: identity)
            stages.append("native service issues a real PKCE-bound one-time code")
            let exchangeURL = URL(string: "https://api.yunle.fun/sso-ticket")!
            let exchange: [String: Any] = [
                "action": "exchangeSsoCode", "clientId": request.clientID, "redirectUri": request.redirectURI,
                "scope": "identity:bootstrap", "code": issued.code, "nonce": nonce, "codeVerifier": verifier,
            ]
            stage = "PKCE rejection"
            var invalid = exchange; invalid["codeVerifier"] = randomValue()
            let rejected = try await send(consumer, url: exchangeURL, fields: invalid, origin: origin)
            guard rejected.status == 403, rejected.body["ok"] as? Bool == false,
                  rejected.body["reason"] as? String == "pkce_invalid" else { throw LiveFailure.protocolResponse }
            stages.append("wrong consumer PKCE verifier is rejected without consuming the code")
            stage = "one-time code consumption"
            let consumed = try await send(consumer, url: exchangeURL, fields: exchange, origin: origin)
            guard consumed.status == 200, consumed.body["ok"] as? Bool == true,
                  let ticket = consumed.body["ticket"] as? String, !ticket.isEmpty,
                  let assertion = consumed.body["identityAssertion"] as? String,
                  assertion.split(separator: ".").count == 3 else { throw LiveFailure.protocolResponse }
            stages.append("real HTTPS consumer exchanges code for a ticket and identity assertion")
            stage = "code replay rejection"
            let replay = try await send(consumer, url: exchangeURL, fields: exchange, origin: origin)
            guard replay.status == 409, replay.body["ok"] as? Bool == false,
                  replay.body["reason"] as? String == "code_used" else { throw LiveFailure.protocolResponse }
            stages.append("a second exchange of the same code is rejected")
            stage = "consumer temporary sign-in"
            let signedIn = try await send(consumer, url: CloudbaseAuthService.gateway.appendingPathComponent("auth/v1/signin/custom"),
                                          fields: ["provider_id": "custom", "ticket": ticket], deviceID: deviceID)
            guard signedIn.status == 200, let token = signedIn.body["access_token"] as? String, !token.isEmpty else {
                throw LiveFailure.protocolResponse
            }
            temporaryToken = token
            let profile = try await CloudbaseAuthService().user(accessToken: token, deviceID: deviceID)
            guard profile.id == identity.userID, profile.username == credential.username, profile.isUsable else {
                throw LiveFailure.identity
            }
            stages.append("consumer custom-ticket sign-in resolves the existing host account")
        } catch { failure = error }
        if let temporaryToken {
            do {
                try await CloudbaseAuthService().signOut(accessToken: temporaryToken, deviceID: deviceID)
                temporarySignedOut = true
            } catch { if failure == nil { failure = error; stage = "consumer sign-out" } }
        }
        for user in accounts.overview.users {
            do {
                try await accounts.remove(user.id)
                hostSignedOut = accounts.notice == nil
            } catch { if failure == nil { failure = error; stage = "host sign-out" } }
        }
        let report: [String: Any] = ["account": credential.id, "stages": stages,
            "consumerResponses": observations,
            "consumerSignedOut": temporarySignedOut, "hostSignedOut": hostSignedOut,
            "hostTokenDeliveredToWebView": false, "realApplicationBFFSession": false]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "native-host-sso-live"; attachment.lifetime = .keepAlways; add(attachment)
        if let failure {
            let category = failure is HostAuthorizationError ? "host protocol" : failure is AccountError ? "account" : "consumer protocol"
            XCTFail("Live SSO failed at \(stage) (\(category)); response contents omitted")
        } else {
            XCTAssertTrue(temporarySignedOut)
            XCTAssertTrue(hostSignedOut)
        }
    }

    private func randomValue() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
    private func send(_ session: URLSession, url: URL, fields: [String: Any], origin: String? = nil,
                      deviceID: String? = nil) async throws -> Reply {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
        if let deviceID { request.setValue(deviceID, forHTTPHeaderField: "x-device-id") }
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LiveFailure.protocolResponse }
        var observation: [String: Any] = ["status": http.statusCode, "mime": http.mimeType ?? "missing",
                                          "host": url.host ?? "missing"]
        let body = data.count <= 128 * 1024 ? (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] : nil
        if let reason = body?["reason"] as? String,
           ["pkce_invalid", "code_used", "phone_verification_required", "not_configured", "registry_invalid",
            "registry_unavailable", "identity_unavailable", "error", "origin_not_allowed", "invalid_request",
            "not_authenticated", "code_binding_invalid", "client_binding_invalid"].contains(reason) {
            observation["reason"] = reason
        }
        observations.append(observation)
        guard http.mimeType?.lowercased() == "application/json", let body else { throw LiveFailure.protocolResponse }
        return Reply(status: http.statusCode, body: body)
    }
    private struct Pool: Decodable { let accounts: [Credential] }
    private struct Credential: Decodable { let id: String; let environment: String; let username: String; let password: String }
    private struct Reply { let status: Int; let body: [String: Any] }
    private enum LiveFailure: Error { case protocolResponse, identity }
    private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
}
