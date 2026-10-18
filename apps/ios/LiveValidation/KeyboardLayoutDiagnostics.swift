import Security
import SwiftUI
import XCTest
@testable import YunleFun

/// Explicit, credential-free probes for the iOS 27 SwiftUI input accessory issue.
/// These remain red while the sheet issue is present; they are not functional
/// acceptance tests and must not be reported as passing UI verification.
@MainActor
final class KeyboardLayoutDiagnostics: XCTestCase {
    private let warnings = RuntimeWarnings()
    override nonisolated func record(_ issue: XCTIssue) {
        if issue.compactDescription.contains("Invalid frame dimension") { warnings.mark() }
        super.record(issue)
    }

    func testMinimalUIKitSheetKeyboardFocusHasNoInvalidFrameWarning() async throws {
        try requireDiagnostics()
        try await checkMinimalKeyboard(style: .pageSheet)
    }

    func testMinimalFullScreenKeyboardFocusHasNoInvalidFrameWarning() async throws {
        try requireDiagnostics()
        try await checkMinimalKeyboard(style: .fullScreen)
    }

    private func checkMinimalKeyboard(style: UIModalPresentationStyle) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        let presenter = try XCTUnwrap(window.rootViewController)
        let page = UIHostingController(rootView: MinimalKeyboardForm())
        page.modalPresentationStyle = style
        presenter.present(page, animated: false)
        defer { page.view.endEditing(true); page.dismiss(animated: false) }
        try await Task.sleep(nanoseconds: 300_000_000)
        page.view.layoutIfNeeded()
        let field = try XCTUnwrap(descendants(page.view).compactMap { $0 as? UITextField }.first { $0.isSecureTextEntry })
        XCTAssertTrue(field.becomeFirstResponder())
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertTrue(field.isFirstResponder)
        page.view.endEditing(true)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(warnings.seen, "A standard SwiftUI keyboard toolbar must not create an invalid frame")
    }

    func testNativePasswordKeyboardFocusHasNoInvalidFrameWarning() async throws {
        try requireDiagnostics()
        let service = "fun.yunle.apps.keyboard-probe." + UUID().uuidString
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary) }
        let accounts = AccountStore(session: AccountSession(vault: KeychainAccountVault(service: service)))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        let presenter = try XCTUnwrap(window.rootViewController)
        let page = UIHostingController(rootView: LoginView().environmentObject(accounts))
        page.modalPresentationStyle = .pageSheet
        presenter.present(page, animated: false)
        defer { page.view.endEditing(true); page.dismiss(animated: false) }
        try await Task.sleep(nanoseconds: 300_000_000)
        page.view.layoutIfNeeded()
        let picker = try XCTUnwrap(descendants(page.view).compactMap { $0 as? UISegmentedControl }.first)
        picker.selectedSegmentIndex = 2; picker.sendActions(for: .valueChanged)
        try await Task.sleep(nanoseconds: 150_000_000)
        page.view.layoutIfNeeded()
        let password = try XCTUnwrap(descendants(page.view).compactMap { $0 as? UITextField }.first { $0.isSecureTextEntry })
        XCTAssertTrue(password.becomeFirstResponder())
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertTrue(password.isFirstResponder)
        XCTAssertNil(accounts.user)
        page.view.endEditing(true)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(password.isFirstResponder)
        XCTAssertFalse(warnings.seen, "Native login keyboard focus must not produce an invalid frame")
    }

    private func descendants(_ root: UIView) -> [UIView] {
        root.subviews.flatMap { [$0] + descendants($0) }
    }
    private func requireDiagnostics() throws {
        guard ProcessInfo.processInfo.environment["YUNLEFUN_UI_LAYOUT_DIAGNOSTICS"] == "1" else {
            throw XCTSkip("Requires an idle dedicated simulator and explicit UI layout diagnostics")
        }
    }
}

private struct MinimalKeyboardForm: View {
    @State private var value = ""
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            Form { SecureField("Password", text: $value).focused($focused) }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focused = false }
                    }
                }
        }
    }
}

private final class RuntimeWarnings: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func mark() { lock.lock(); defer { lock.unlock() }; value = true }
    var seen: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
