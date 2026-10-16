import SwiftUI

struct MyReportsView: View {
    @EnvironmentObject private var accounts: AccountStore
    var body: some View { MyReportsContent(accounts: accounts) }
}
private struct MyReportsContent: View {
    @ObservedObject var accounts: AccountStore
    @StateObject private var model: MyReportsStore
    @State private var showLogin = false
    init(accounts: AccountStore) {
        self.accounts = accounts
        _model = StateObject(wrappedValue: MyReportsStore(accounts: accounts))
    }
    var body: some View {
        List {
            if accounts.user == nil {
                ContentStateView(title: "登录后查看举报记录", systemImage: "person.crop.circle",
                                 message: "你提交的举报及处理状态会显示在这里。")
                Button("登录云乐坊") { showLogin = true }
            } else {
                if model.isLoading || (!model.hasLoaded && model.error == nil) { ProgressView("正在载入举报记录") }
                if let error = model.error {
                    Label(error, systemImage: "wifi.exclamationmark")
                    Button("重试") { Task { await model.refresh() } }
                } else if model.hasLoaded && !model.isLoading && model.reports.isEmpty {
                    ContentStateView(title: "还没有举报记录", systemImage: "flag",
                                     message: "在应用或评价中提交举报后，可在这里查看状态。")
                }
                ForEach(model.reports) { report in
                    Section {
                        LabeledContent("对象", value: report.appName ?? report.appKey ?? (report.targetType == .app ? "应用" : "评价"))
                        LabeledContent("类型", value: report.targetType == .app ? "应用举报" : "评价举报")
                        LabeledContent("原因", value: report.reason.label)
                        LabeledContent("状态", value: report.status.label)
                        if let detail = report.detail, !detail.isEmpty { Text(detail).textSelection(.enabled) }
                        Text(Date(timeIntervalSince1970: report.createdAt / 1000), format: .dateTime.year().month().day())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section { Text("显示最近 50 条举报记录。").font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("我的举报").navigationBarTitleDisplayMode(.inline)
        .task(id: accounts.identityGeneration) { await model.refresh() }
        .refreshable { await model.refresh() }
        .sheet(isPresented: $showLogin) {
            LoginView(continuationMessage: "登录后可查看你的举报及处理状态。").environmentObject(accounts)
        }
    }
}
