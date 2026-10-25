import Foundation
import Security

struct AuthorizationSheetContent {
    let applicationName: String
    let applicationOrigin: String
    let applicationIconURL: String?
    let accountName: String
    let accountAvatarURL: String?
    let permissionDescription: String
    let authorizationNotice: String?
}

enum AuthorizationSheetChoice: String {
    case current
    case other
    case cancel
}

/// The same page-facing transport is installed by each native WebKit host.
/// Native dispatchers remain responsible for source checks and capability access.
enum YunleHostBridgeScript {
    static let source = """
    (function () {
      if (window.ylf) { return }
      function invoke(method, params) {
        return window.webkit.messageHandlers.ylf.postMessage({ method: method, params: params || {} })
      }
      window.ylf = {
        version: 7,
        inYunleApp: true,
        invoke: invoke,
        canIUse: function (method) { return invoke('canIUse', { method: method }) },
        authorize: function (params) { return invoke('authorize', params) },
        openAuthSession: function (params) { return invoke('openAuthSession', params) },
        getEnv: function () { return invoke('getEnv') },
        hideCapsule: function () { return invoke('setCapsuleVisible', { visible: false }) },
        showCapsule: function () { return invoke('setCapsuleVisible', { visible: true }) },
        hideTitleBar: function () { return invoke('setTitleBarVisible', { visible: false }) },
        showTitleBar: function () { return invoke('setTitleBarVisible', { visible: true }) },
        closeBrowser: function () { return invoke('close') },
        haptic: function (style) { return invoke('haptic', { style: style }) },
        setClipboard: function (text) { return invoke('setClipboard', { text: text }) },
      }
    })()
    """
}

struct NativeSsoRequest {
    let clientId: String
    let codeChallenge: String
    let nonce: String
    let redirectUri: String
    let scope: String
    let acquisitionJSON: String?
}

enum NativeSsoResult {
    case success(code: String, issuer: String)
    case denied
}

enum NativeSsoProtocol {
    private static let issuer = "https://www.yunle.fun"

    static func readRequest(_ input: [String: Any]) -> NativeSsoRequest? {
        guard let clientId = input["clientId"] as? String,
              let codeChallenge = input["codeChallenge"] as? String,
              let nonce = input["nonce"] as? String,
              let redirectUri = input["redirectUri"] as? String,
              let scopes = input["scope"] as? [String],
              scopes == ["identity:bootstrap"],
              input["codeChallengeMethod"] as? String == "S256",
              isClientId(clientId),
              isValue(codeChallenge),
              isValue(nonce),
              isSecureRedirect(redirectUri)
        else {
            return nil
        }
        return NativeSsoRequest(
            clientId: clientId,
            codeChallenge: codeChallenge,
            nonce: nonce,
            redirectUri: redirectUri,
            scope: scopes[0],
            acquisitionJSON: readAcquisitionJSON(input["acquisition"]))
    }

    static func authorizationURL(request: NativeSsoRequest, state: String) -> URL? {
        guard isValue(state) else { return nil }
        let callback = "yunlefun://auth/sso?state=\(state)"
        var components = URLComponents(string: "\(issuer)/auth/sso")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: request.clientId),
            URLQueryItem(name: "redirect_uri", value: request.redirectUri),
            URLQueryItem(name: "scope", value: request.scope),
            URLQueryItem(name: "nonce", value: request.nonce),
            URLQueryItem(name: "code_challenge", value: request.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
            URLQueryItem(name: "native_callback_uri", value: callback),
        ]
        if let acquisitionJSON = request.acquisitionJSON {
            components?.queryItems?.append(URLQueryItem(name: "acquisition", value: acquisitionJSON))
        }
        return components?.url
    }

    // Optional analytics never changes the authorization/PKCE acceptance rules.
    static func readAcquisitionJSON(_ input: Any?) -> String? {
        guard let context = input as? [String: Any],
              JSONSerialization.isValidJSONObject(context),
              let raw = try? JSONSerialization.data(withJSONObject: context), raw.count <= 4096,
              let version = context["version"] as? NSNumber,
              String(cString: version.objCType) != "c", version.doubleValue == 1,
              let first = readAcquisitionTouch(context["firstTouch"]),
              let current = readAcquisitionTouch(context["registerTouch"]),
              let data = try? JSONSerialization.data(withJSONObject: [
                "version": 1, "firstTouch": first, "registerTouch": current,
              ]), data.count <= 4096
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func readAcquisitionTouch(_ input: Any?) -> [String: Any]? {
        guard let touch = input as? [String: Any],
              let timestamp = touch["capturedAt"] as? NSNumber,
              String(cString: timestamp.objCType) != "c",
              timestamp.doubleValue > 0, timestamp.doubleValue <= 9007199254740991,
              timestamp.doubleValue.rounded() == timestamp.doubleValue
        else { return nil }
        var output: [String: Any] = ["capturedAt": timestamp]
        for key in ["landingHost", "referrerHost", "landingPath", "utmSource", "utmMedium", "utmCampaign"] {
            guard let value = touch[key] as? String,
                  !value.unicodeScalars.contains(where: { $0.value < 32 || (127...159).contains($0.value) })
            else { return nil }
            if key == "landingHost" || key == "referrerHost" {
                let host = value.lowercased()
                guard host.count <= 253,
                      (host.isEmpty && key == "referrerHost") ||
                      (host.range(of: "^[a-z0-9.-]+$", options: .regularExpression) != nil &&
                       host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
                         !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-")
                       })
                else { return nil }
                output[key] = host
            } else if key == "landingPath" {
                guard value.hasPrefix("/"), !value.hasPrefix("//"), !value.contains("\\"),
                      value.range(of: "%0[0-9a-f]|%1[0-9a-f]|%7f", options: [.regularExpression, .caseInsensitive]) == nil
                else { return nil }
                output[key] = String(value.split(whereSeparator: { $0 == "?" || $0 == "#" }).first?.prefix(256) ?? "")
            } else {
                guard value.count <= 120,
                      value.range(of: "^[\\p{L}\\p{N}\\p{M} ._/-]*$", options: .regularExpression) != nil
                else { return nil }
                output[key] = value.trimmingCharacters(in: .whitespaces)
            }
        }
        return output
    }

    static func readCallback(
        _ callbackURL: URL,
        expectedState: String,
        request: NativeSsoRequest
    ) -> NativeSsoResult? {
        guard let callback = URLComponents(
            url: callbackURL,
            resolvingAgainstBaseURL: false),
            callback.scheme == "yunlefun",
            callback.host == "auth",
            callback.path == "/sso",
            callback.fragment == nil,
            let items = callback.queryItems,
            items.count == 2,
            Set(items.map(\.name)) == Set(["state", "result"]),
            items.first(where: { $0.name == "state" })?.value == expectedState,
            let resultValue = items.first(where: { $0.name == "result" })?.value,
            let resultURL = URL(string: resultValue),
            var result = URLComponents(url: resultURL, resolvingAgainstBaseURL: false),
            let fragment = result.fragment,
            fragment.hasPrefix("ylf_sso="),
            !fragment.contains("&")
        else {
            return nil
        }
        result.fragment = nil
        guard result.url?.absoluteString == request.redirectUri else { return nil }

        let encoded = String(fragment.dropFirst("ylf_sso=".count))
        guard let data = decodeBase64Url(encoded),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["nonce"] as? String == request.nonce,
              payload["iss"] as? String == issuer,
              payload["ticket"] == nil,
              payload["session"] == nil,
              payload["access_token"] == nil,
              payload["refresh_token"] == nil
        else {
            return nil
        }
        if payload["ok"] as? Bool == true,
           let code = payload["code"] as? String,
           isValue(code) {
            return .success(code: code, issuer: issuer)
        }
        return payload["ok"] as? Bool == false
            && payload["reason"] as? String == "access_denied"
            ? .denied
            : nil
    }

    static func randomState() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return nil
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func isClientId(_ value: String) -> Bool {
        value.range(
            of: "^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$",
            options: .regularExpression) != nil
    }

    private static func isValue(_ value: String) -> Bool {
        value.count == 43 && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
        }
    }

    private static func isSecureRedirect(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              components.scheme == "https",
              !(components.host ?? "").isEmpty,
              components.user == nil,
              components.password == nil,
              components.fragment == nil
        else {
            return false
        }
        return components.url?.absoluteString == value
    }

    private static func decodeBase64Url(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
        return Data(base64Encoded: base64)
    }
}
