import XCTest
#if os(macOS)
@testable import YunleFunMac
#else
@testable import YunleFun
#endif

final class HostAuthorizationProtocolTests: XCTestCase {
    private let state = String(repeating: "s", count: 43)
    private let code = String(repeating: "x", count: 43)

    func testSystemAuthorizationPreservesConsumerPKCEAndUsesStateBoundHostCallback() throws {
        let request = try XCTUnwrap(NativeSsoProtocol.readRequest(ssoParameters()))
        let url = try XCTUnwrap(NativeSsoProtocol.authorizationURL(request: request, state: state))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: try XCTUnwrap(parts.queryItems).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(parts.scheme, "https")
        XCTAssertEqual(parts.host, "www.yunle.fun")
        XCTAssertEqual(parts.path, "/auth/sso")
        XCTAssertEqual(query["code_challenge"], request.codeChallenge)
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["nonce"], request.nonce)
        XCTAssertEqual(query["redirect_uri"], request.redirectUri)
        XCTAssertEqual(query["prompt"], "select_account")
        XCTAssertEqual(query["native_callback_uri"], "yunlefun://auth/sso?state=\(state)")
    }

    func testCallbackRejectsSubstitutedBindingAndHostCredentials() throws {
        let request = try XCTUnwrap(NativeSsoProtocol.readRequest(ssoParameters()))
        let payload: [String: Any] = ["ok": true, "code": code, "nonce": request.nonce,
                                      "iss": HostSsoPolicy.issuer]
        let valid = try callback(payload, redirect: request.redirectUri)
        guard case .success(let returnedCode, let issuer) = NativeSsoProtocol.readCallback(
            valid, expectedState: state, request: request) else {
            return XCTFail("A bound callback should return the consumer's one-time code")
        }
        XCTAssertEqual(returnedCode, code)
        XCTAssertEqual(issuer, HostSsoPolicy.issuer)
        XCTAssertNil(NativeSsoProtocol.readCallback(valid, expectedState: String(repeating: "t", count: 43), request: request))
        let wrongRedirect = try callback(payload, redirect: "https://other.example.invalid/")
        XCTAssertNil(NativeSsoProtocol.readCallback(wrongRedirect, expectedState: state, request: request))
        for (key, value) in [
            ("nonce", String(repeating: "z", count: 43)), ("iss", "https://other.example.invalid"),
            ("ticket", "synthetic-ticket"), ("session", "synthetic-session"),
            ("access_token", "synthetic-access"), ("refresh_token", "synthetic-refresh"),
        ] {
            var changed = payload
            changed[key] = value
            let url = try callback(changed, redirect: request.redirectUri)
            XCTAssertNil(NativeSsoProtocol.readCallback(url, expectedState: state, request: request), key)
        }
        var duplicate = try XCTUnwrap(URLComponents(url: valid, resolvingAgainstBaseURL: false))
        duplicate.queryItems?.append(URLQueryItem(name: "state", value: state))
        XCTAssertNil(NativeSsoProtocol.readCallback(try XCTUnwrap(duplicate.url), expectedState: state, request: request))
    }

    func testOptionalAcquisitionStripsPrivateURLDataWithoutChangingAuthorization() throws {
        let touch: [String: Any] = [
            "capturedAt": 1_000, "landingHost": "dayun-kicker.yunle.fun",
            "landingPath": "/random?token=private#secret", "referrerHost": "www.baidu.com",
            "utmSource": "百度", "utmMedium": "organic", "utmCampaign": "",
        ]
        var input = ssoParameters()
        input["acquisition"] = ["version": 1, "firstTouch": touch, "registerTouch": touch, "unknown": "private"]
        let request = try XCTUnwrap(NativeSsoProtocol.readRequest(input))
        let data = try XCTUnwrap(request.acquisitionJSON?.data(using: .utf8))
        let context = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(context["unknown"])
        let first = try XCTUnwrap(context["firstTouch"] as? [String: Any])
        XCTAssertEqual(first["landingPath"] as? String, "/random")
        XCTAssertEqual(first["utmSource"] as? String, "百度")
        input["acquisition"] = ["version": true, "firstTouch": touch, "registerTouch": touch]
        let withoutAnalytics = try XCTUnwrap(NativeSsoProtocol.readRequest(input))
        XCTAssertNil(withoutAnalytics.acquisitionJSON)
        XCTAssertEqual(withoutAnalytics.codeChallenge, request.codeChallenge)
        XCTAssertEqual(withoutAnalytics.nonce, request.nonce)
        XCTAssertEqual(withoutAnalytics.redirectUri, request.redirectUri)
    }

    private func callback(_ payload: [String: Any], redirect: String) throws -> URL {
        let encoded = try JSONSerialization.data(withJSONObject: payload).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var url = try XCTUnwrap(URLComponents(string: "yunlefun://auth/sso"))
        url.queryItems = [URLQueryItem(name: "state", value: state),
                          URLQueryItem(name: "result", value: redirect + "#ylf_sso=" + encoded)]
        return try XCTUnwrap(url.url)
    }
}
