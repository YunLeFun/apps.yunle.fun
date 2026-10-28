import SwiftUI

struct SharedFeedbackReceiptsSection: View {
    @ObservedObject var accounts: AccountStore
    let history: SharedFeedbackHistory
    let onOpen: (SupportTicketPage) -> Void
    let onRequestClear: (SharedFeedbackContext, @escaping (Error?) -> Void) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var records: [SharedFeedbackRecord] = []
    @State private var context: SharedFeedbackContext?
    @State private var error: String?

    var body: some View {
        Section {
            if let error {
                Text(error).accessibilityIdentifier("feedback.shared.error")
                Button("重新读取分享反馈") { reload() }
            }
            if records.isEmpty && error == nil {
                Text("截图后可在系统分享菜单中选择“云乐坊”发起反馈，提交的工单会显示在这里。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(records) { record in
                Button {
                    if record.ticketURL != nil { onOpen(SupportTicketPage(receipt: record.receipt)) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(SupportProduct.title(record.receipt.productId))
                        Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(record.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("查看分享反馈工单，\(SupportProduct.title(record.receipt.productId))，\(record.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .accessibilityIdentifier("feedback.shared.ticket")
            }
            if !records.isEmpty {
                Button("清除本机分享反馈记录", role: .destructive) {
                    guard let context else { return }
                    onRequestClear(context) { failure in
                        if let failure { error = (failure as? SharedFeedbackHistoryError)?.message ?? "暂时无法清除记录，请稍后重试。" }
                        else { reload() }
                    }
                }
                    .accessibilityIdentifier("feedback.shared.clear")
            }
        } header: { Text("从系统分享提交的反馈") }
        footer: { Text("最多保留 20 条本机访客工单链接，切换账号后清空。链接仅供自己查看，请勿转发。") }
        .task(id: accounts.identityGeneration) { reload() }
        .onChange(of: accounts.isRestoring) { if !$0 { reload() } }
        .onChange(of: scenePhase) { if $0 == .active { reload() } }
    }

    private func reload() {
        guard !accounts.isRestoring else { return }
        do {
            try history.activate(userID: accounts.user?.id, channel: .current)
            context = try history.rememberedContext()
            records = try context.map { try history.records(expected: $0) } ?? []
            error = nil
        } catch {
            context = nil; records = []
            self.error = (error as? SharedFeedbackHistoryError)?.message ?? "分享反馈记录暂时无法读取，请稍后重试。"
        }
    }
}
