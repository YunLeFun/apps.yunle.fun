import SwiftUI
import YunleSupportUI

/// Direct entry to the complete Support website, with the same account boundary
/// and SSO proof as the native feedback center.
struct SupportWebsiteView: View {
    @ObservedObject private var accounts: AccountStore
    @StateObject private var model: SupportCenterStore
    @Environment(\.dismiss) private var dismiss

    init(accounts: AccountStore) {
        self.accounts = accounts
        _model = StateObject(wrappedValue: SupportCenterStore(accounts: accounts))
    }

    var body: some View {
        ZStack {
            if accounts.user == nil || model.access != nil {
                SupportBrowserView(page: SupportBrowserPage(url: SupportConfiguration(productID: "www", appName: "云乐坊").url(for: .help)!, access: model.access))
            } else {
                NavigationStack {
                    List {
                        if model.isLoading { ProgressView("正在登录支持中心") }
                        if let error = model.error {
                            Text(error)
                            Button(model.needsConsent ? "允许使用当前账号并打开" : "重试") {
                                Task { await model.load(.compose, consent: model.needsConsent) }
                            }
                        }
                    }
                    .navigationTitle("云乐坊支持中心").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
                }
            }
        }
        .id(accounts.identityGeneration)
        .task(id: accounts.identityGeneration) {
            if accounts.user != nil { await model.load(.compose) }
        }
        .onDisappear { model.close() }
    }
}
