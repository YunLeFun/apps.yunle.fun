import SwiftUI

struct SupportTicketPage: Identifiable {
    let id = UUID()
    let receipt: SupportFeedbackReceipt
    var access: SupportAccess? = nil
}

/// Native requester view. The Support service remains the source of truth.
struct SupportTicketView: View {
    let page: SupportTicketPage
    private let client = SupportTicketClient()
    @State private var snapshot: SupportTicketSnapshot?
    @State private var error: String?
    @State private var retry = UUID()
    @State private var browser: SupportBrowserPage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let snapshot {
                    Section {
                        Text(snapshot.detail.ticket.title).font(.headline).textSelection(.enabled)
                        LabeledContent("产品", value: SupportProduct.title(snapshot.detail.ticket.productId))
                        LabeledContent("状态", value: snapshot.detail.ticket.statusTitle)
                        Text(snapshot.detail.ticket.number).font(.caption.monospaced()).foregroundStyle(.secondary)
                    } header: { Text("私密工单") }
                    Section("交流记录") {
                        ForEach(snapshot.detail.messages) { message in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(message.author == "you" ? "你" : "云乐坊支持团队").font(.subheadline.bold())
                                Text(message.content).textSelection(.enabled)
                                Text(message.createdAt).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                    }
                    if !snapshot.screenshots.isEmpty {
                        Section("截图") {
                            ForEach(Array(snapshot.screenshots.enumerated()), id: \.element.id) { index, item in
                                SupportTicketScreenshotRow(item: item, index: index, snapshot: snapshot, client: client)
                            }
                        }
                    }
                    if let url = SupportFeedbackClient.ticketURL(page.receipt) {
                        Section {
                            Button { browser = SupportBrowserPage(url: url, access: page.access) } label: {
                                Label("在网页中回复或继续处理", systemImage: "globe")
                            }
                        } footer: { Text("工单和截图仅自己与支持人员可见。回复及更多操作可在完整支持中心继续。") }
                    }
                } else if let error {
                    Section {
                        Text(error).accessibilityIdentifier("support.ticket.error")
                        Button("重新读取工单") { retry = UUID() }
                    }
                } else { ProgressView("正在读取工单") }
            }
            .navigationTitle("反馈工单").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("support.ticket.close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { retry = UUID() } label: { Label("刷新工单", systemImage: "arrow.clockwise") }
                        .accessibilityIdentifier("support.ticket.refresh")
                }
            }
            .task(id: retry) {
                snapshot = nil; error = nil
                do {
                    let loaded = try await client.open(page.receipt, cookies: page.access?.cookies ?? [])
                    try Task.checkCancellation(); snapshot = loaded
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = (error as? SupportTicketError)?.message ?? SupportTicketError.unavailable.message
                }
            }
            .sheet(item: $browser) { SupportBrowserView(page: $0) }
        }
    }
}

private struct SupportTicketScreenshotRow: View {
    let item: SupportTicketScreenshot
    let index: Int
    let snapshot: SupportTicketSnapshot
    let client: SupportTicketClient
    @State private var data: Data?
    @State private var error: String?
    @State private var retry = UUID()

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                NavigationLink {
                    ScreenshotPreview(data: data, imageLabel: "截图 \(index + 1) 完整预览")
                } label: {
                    HStack(spacing: 12) {
                        Image(uiImage: image).resizable().scaledToFit().frame(width: 64, height: 80).accessibilityHidden(true)
                        Text("预览截图 \(index + 1)")
                    }
                }
                .accessibilityIdentifier("support.ticket.screenshot.\(index)")
            } else if let error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).font(.footnote)
                    Button("重新读取截图 \(index + 1)") { retry = UUID() }
                }
            } else { ProgressView("正在读取截图 \(index + 1)") }
        }
        .task(id: retry) {
            error = nil
            do {
                let loaded = try await client.screenshot(item, in: snapshot)
                try Task.checkCancellation(); data = loaded
            } catch {
                guard !Task.isCancelled else { return }
                self.error = (error as? SupportTicketError)?.message ?? SupportTicketError.unavailable.message
            }
        }
    }
}
