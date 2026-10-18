import SwiftUI

struct WalletView: View {
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var wallet: WalletStore
    @EnvironmentObject private var purchases: PurchaseCoordinator
    @State private var showLogin = false
    @State private var legacyConfirmation: LegacyPurchaseConfirmation?
    var body: some View {
        List {
            if accounts.user == nil { WalletLoginSection(showLogin: $showLogin) }
            else {
                WalletBalanceSection()
                Section {
                    NavigationLink { MembershipView() } label: { Label("云乐坊会员", systemImage: "crown") }
                }
                CommerceProductsSection(membership: false)
                CommerceStatusSection(confirmation: $legacyConfirmation)
                Section("云币流水") {
                    if wallet.isLoadingTransactions && wallet.entries.isEmpty { ProgressView("正在读取流水") }
                    else if wallet.transactionsError == nil && wallet.entries.isEmpty { Text("暂无流水").foregroundStyle(.secondary) }
                    ForEach(wallet.entries) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.title)
                                Spacer()
                                Text(item.amount.formatted(.number.sign(strategy: .always())) + " 云币")
                                    .foregroundStyle(item.amount >= 0 ? Color.green : Color.primary)
                            }
                            HStack {
                                Text(item.date, format: .dateTime.year().month().day().hour().minute())
                                Spacer()
                                Text("余额 \(item.balanceAfter.formatted())")
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine).padding(.vertical, 3)
                    }
                    if let error = wallet.transactionsError {
                        Label(error, systemImage: "exclamationmark.triangle")
                        Button("重试读取流水") { Task { await wallet.loadTransactions(reset: wallet.entries.isEmpty) } }
                    } else if wallet.nextSkip != nil && !wallet.entries.isEmpty {
                        Button("加载更多") { Task { await wallet.loadTransactions() } }.disabled(wallet.isLoadingTransactions)
                    }
                }
            }
        }
        .navigationTitle("钱包")
        .sheet(isPresented: $showLogin) { LoginView(continuationMessage: "登录后查看云币、会员与购买记录。") }
        .modifier(PurchaseConfirmationModifier(confirmation: $legacyConfirmation))
        .onChange(of: accounts.identityGeneration) { _ in showLogin = false }
        .refreshable { await wallet.reconcileAndRefresh() }
        .task(id: accounts.identityGeneration) {
            guard accounts.user != nil else { return }
            await wallet.reconcileAndRefresh(); await purchases.loadProducts(); await purchases.processUnfinished()
        }
    }
}

struct MembershipView: View {
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var wallet: WalletStore
    @EnvironmentObject private var purchases: PurchaseCoordinator
    @State private var showLogin = false
    @State private var legacyConfirmation: LegacyPurchaseConfirmation?
    var body: some View {
        List {
            if accounts.user == nil { WalletLoginSection(showLogin: $showLogin) }
            else {
                Section("会员状态") {
                    if let membership = wallet.snapshot?.membership {
                        LabeledContent(membership.title, value: membership.isActive ? "已开通" : "当前未生效")
                        if let date = membership.expiration { LabeledContent("到期日期") { Text(date, format: .dateTime.year().month().day()) } }
                    } else if wallet.isLoading { ProgressView("正在读取会员状态") }
                    else { Text("尚未获取会员状态").foregroundStyle(.secondary) }
                    if let error = wallet.snapshotError {
                        Label(error, systemImage: "exclamationmark.triangle")
                        Button("重试读取会员") { Task { await wallet.refreshAccount() } }
                    }
                }
                Section {
                    Label("用户数据同步", systemImage: "icloud")
                    Label("收藏与历史记录", systemImage: "bookmark")
                } header: { Text("会员权益") } footer: { Text("权益由云乐坊账户统一记录，在支持对应能力的云应用中使用。") }
                CommerceProductsSection(membership: true)
                CommerceStatusSection(confirmation: $legacyConfirmation)
            }
            Section {
                Link("隐私政策", destination: URL(string: "https://www.yunle.fun/docs/privacy-policy")!)
                Link("服务条款", destination: URL(string: "https://www.yunle.fun/docs/terms-of-service")!)
            }
        }
        .navigationTitle("云乐坊会员")
        .sheet(isPresented: $showLogin) { LoginView(continuationMessage: "登录后查看云币、会员与购买记录。") }
        .modifier(PurchaseConfirmationModifier(confirmation: $legacyConfirmation))
        .onChange(of: accounts.identityGeneration) { _ in showLogin = false }
        .refreshable { await wallet.refreshAccount() }
        .task(id: accounts.identityGeneration) {
            guard accounts.user != nil else { return }
            await wallet.refreshAccount(); await purchases.loadProducts(); await purchases.processUnfinished()
        }
    }
}

private struct WalletLoginSection: View {
    @Binding var showLogin: Bool
    var body: some View {
        Section {
            Label("登录后查看云币与会员", systemImage: "wallet.pass")
            Text("购买记录与权益保存在对应的云乐坊账号中。").foregroundStyle(.secondary)
            Button("登录云乐坊") { showLogin = true }
        }
    }
}
private struct WalletBalanceSection: View {
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var wallet: WalletStore
    var body: some View {
        Section {
            if let snapshot = wallet.snapshot {
                LabeledContent("云币余额") {
                    WalletCoinBalance(coin: snapshot.coin)
                }
            } else if wallet.isLoading { ProgressView("正在读取余额") }
            else { Text("尚未获取余额").foregroundStyle(.secondary) }
            LabeledContent("当前账号", value: accounts.user?.displayName ?? "")
            if let date = wallet.checkedAt { Text("获取于 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            if let error = wallet.snapshotError {
                Label(error, systemImage: "exclamationmark.triangle")
                Button("重试读取余额") { Task { await wallet.refreshAccount() } }
            }
            if let error = wallet.reconciliationError {
                Label(error, systemImage: "info.circle").foregroundStyle(.secondary)
                Button("重试核对历史订单") { Task { await wallet.reconcileAndRefresh() } }
            }
        } header: { Text("账户") }
    }
}
struct WalletCoinBalance: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let coin: Int64
    var body: some View {
        Text(coin.formatted()).font(.title2.bold()).monospacedDigit()
            .numericTransition(Double(coin))
            .animation(Motion.standard(reduceMotion: reduceMotion), value: coin)
    }
}
private struct CommerceProductsSection: View {
    let membership: Bool
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var purchases: PurchaseCoordinator
    private var products: [CommerceProduct] {
        purchases.products.filter { membership ? NativeIapCatalog.memberships[$0.id] != nil : NativeIapCatalog.coinAmounts[$0.id] != nil }
            .sorted { left, right in
                if membership { return left.id < right.id }
                return (NativeIapCatalog.coinAmounts[left.id] ?? 0) < (NativeIapCatalog.coinAmounts[right.id] ?? 0)
            }
    }
    var body: some View {
        Section {
            if purchases.productsLoading { ProgressView("正在读取 App Store 商品") }
            ForEach(products) { product in
                Button { Task { await purchases.purchase(product.id) } } label: {
                    HStack {
                        Text(product.title)
                        Spacer()
                        Text(product.displayPrice).fontWeight(.semibold)
                    }.frame(minHeight: 32)
                }.disabled(purchases.isBusy)
            }
            if let error = purchases.productsError {
                Text(error).foregroundStyle(.secondary)
                Button("重试读取商品") { Task { await purchases.loadProducts() } }
            } else if products.isEmpty && !purchases.productsLoading {
                Text("此类 App Store 商品暂不可用。").foregroundStyle(.secondary)
                Button("重试读取商品") { Task { await purchases.loadProducts() } }
            }
        } header: { Text(membership ? "开通或延长会员" : "充值云币") }
        footer: {
            Text(membership ? "会员为非自动续期套餐。购买与恢复将核对到当前云乐坊账号：\(accounts.user?.displayName ?? "")。" :
                    "价格以 App Store 显示为准，购买核对到当前云乐坊账号。")
        }
    }
}
private struct CommerceStatusSection: View {
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var purchases: PurchaseCoordinator
    @Binding var confirmation: LegacyPurchaseConfirmation?
    var body: some View {
        Section {
            if purchases.isBusy { ProgressView("正在处理购买") }
            if let notice = purchases.notice { Label(notice, systemImage: "info.circle") }
            if let error = purchases.error {
                Label(error, systemImage: "exclamationmark.triangle")
                Button("核对未完成购买") { Task { await purchases.processUnfinished() } }.disabled(purchases.isBusy)
            }
            if let value = purchases.legacyConfirmation {
                Button("核对 \(value.transactionIDs.count) 笔旧购买") { confirmation = value }.disabled(purchases.isBusy)
            }
            Button("恢复购买") { Task { await purchases.restore() } }.disabled(purchases.isBusy)
        }
    }
}
private struct PurchaseConfirmationModifier: ViewModifier {
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var purchases: PurchaseCoordinator
    @Binding var confirmation: LegacyPurchaseConfirmation?
    func body(content: Content) -> some View {
        content.confirmationDialog("将旧购买交给当前账号核对？", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
            if let value = confirmation {
                Button("交给当前账号核对") { confirmation = nil; Task { await purchases.confirmLegacy(value) } }
            }
            Button("取消", role: .cancel) { confirmation = nil }
        } message: { Text("这些购买没有标记云乐坊账号。请确认当前是原购买账号：\(accounts.user?.displayName ?? "")。未绑定的旧交易会首次绑定当前账号，已绑定其他账号的交易仍会被服务端拒绝。") }
        .onChange(of: accounts.identityGeneration) { _ in confirmation = nil }
    }
}
