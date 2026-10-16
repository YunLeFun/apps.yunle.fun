import SwiftUI

enum ApplicationAcquisitionIntent { case install, open }
struct ApplicationAcquisitionView: View {
    @ObservedObject var store: ApplicationAcquisitionStore
    let intent: ApplicationAcquisitionIntent
    let complete: (ApplicationAccessPermit) -> Void
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var showLogin = false
    @State private var showConfirmation = false
    @State private var confirmation: ApplicationCoinConfirmation?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        ApplicationIcon(application: store.application, size: 64)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.application.name).font(.headline)
                            Text(intent == .install ? "加入云居，随时打开" : "确认应用使用权限").foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }
                if accounts.user == nil {
                    Section {
                        Text("登录后确认会员、云币与已购权益。")
                        Button("登录云乐坊") { showLogin = true }
                    }
                } else {
                    Section {
                        LabeledContent("当前账号", value: accounts.user?.displayName ?? "")
                        if store.isBusy { ProgressView("正在核对使用条件") }
                        if let quote = store.quote {
                            conditions(quote)
                        } else if !store.isBusy {
                            Button("重新核对使用条件") { Task { await store.refresh() } }
                        }
                        if let error = store.error { Label(error, systemImage: "exclamationmark.triangle") }
                    }
                    if let quote = store.quote, quote.state == .membershipRequired || quote.state == .purchaseRequired {
                        Section {
                            NavigationLink("前往钱包") { WalletView() }
                            NavigationLink("查看会员") { MembershipView() }
                        } footer: { Text("返回后请刷新使用条件，账户权益以服务端核对结果为准。") }
                    }
                }
            }
            .navigationTitle(intent == .install ? "获取应用" : "打开应用")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .refreshable { await store.refresh() }
            .task(id: accounts.identityGeneration) { showConfirmation = false; confirmation = nil; await store.refresh() }
        }
        .sheet(isPresented: $showLogin) { LoginView(continuationMessage: "登录后继续获取与打开应用。") }
        .confirmationDialog("确认使用 \(confirmation?.coinCost ?? 0) 云币？", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button("确认使用云币") {
                guard let confirmation else { return }
                Task { if let permit = await store.purchase(confirmation) { complete(permit) } }
            }
            Button("取消", role: .cancel) { confirmation = nil }
        } message: { Text("一次购买后，可在当前云乐坊账号中继续使用这个应用。") }
    }
    @ViewBuilder private func conditions(_ quote: ApplicationAcquisitionQuote) -> some View {
        switch quote.state {
        case .allowed:
            Label(quote.reason == "purchased" ? "当前账号已购买" : quote.reason == "member" ? "会员权益可用" : "可以使用", systemImage: "checkmark.circle")
            Button(intent == .install ? "加入云居" : "打开应用") {
                Task { if let permit = await store.refresh() { complete(permit) } }
            }.disabled(store.isBusy)
        case .purchaseRequired:
            LabeledContent("应用价格", value: "\(quote.coinCost.formatted()) 云币")
            LabeledContent("云币余额", value: "\(quote.balance.formatted()) 云币")
            if quote.balance < quote.coinCost { Label("云币余额不足", systemImage: "info.circle") }
            Button("使用云币获取") { confirmation = store.confirmation; showConfirmation = confirmation != nil }
                .disabled(store.confirmation == nil)
        case .membershipRequired:
            Label("需要有效会员", systemImage: "crown")
        case .invitationRequired:
            Label("需要应用邀请", systemImage: "lock")
            Text("会员与云币购买无法替代应用邀请。").foregroundStyle(.secondary)
        }
        Button("刷新使用条件") { Task { await store.refresh() } }.disabled(store.isBusy)
    }
}
