import SwiftUI

@MainActor
struct ApplicationShareCatalogView: View {
    @Environment(\.dismiss) private var dismiss
    private let exporter: ApplicationShareExporter
    @State private var slug: String
    @State private var style: ExportStyle
    @State private var wholeCatalog = false
    @State private var request: Request?
    @State private var busy = false
    @State private var completed = 0
    @State private var total = 0
    @State private var current = ""
    @State private var issue: String?
    @State private var directory: ApplicationShareExportDirectory?
    @State private var sheet: Sheet?
    @State private var saved = false

    init(slug: String, appearance: ApplicationShareAppearance, exporter: ApplicationShareExporter? = nil) {
        self.exporter = exporter ?? ApplicationShareExporter()
        _slug = State(initialValue: slug)
        _style = State(initialValue: appearance == .dark ? .dark : .light)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("单个应用") {
                    TextField("应用 slug，如 dayun-kicker", text: $slug)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("share.catalog.slug")
                    Button("预览应用") { start(.preview) }
                        .disabled(busy || slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("share.catalog.preview")
                }
                Section {
                    Picker("卡片外观", selection: $style) {
                        ForEach(ExportStyle.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("share.catalog.appearance")
                    Toggle("导出全部公开应用", isOn: $wholeCatalog)
                        .accessibilityIdentifier("share.catalog.all")
                    Button(wholeCatalog ? "生成公开目录卡片" : "生成当前应用卡片") { start(.export) }
                        .disabled(busy || (!wholeCatalog && slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        .accessibilityIdentifier("share.catalog.generate")
                } header: { Text("目录导出") }
                footer: { Text("PNG 尺寸 1080 × 1620，按应用 slug 命名。每个应用读取最新公开详情；图标不可用时使用备用图标，失败项会列入导出清单。") }
                .disabled(busy)
                if busy {
                    Section {
                        if total > 0 {
                            ProgressView(value: Double(completed), total: Double(total)) { Text("正在生成 \(completed)/\(total)") }
                            Text(current).font(.caption).foregroundStyle(.secondary)
                        } else { ProgressView("正在读取公开应用") }
                        Button("取消生成", role: .cancel) { request = nil }
                            .accessibilityIdentifier("share.catalog.cancel")
                    }
                }
                if let directory {
                    Section("导出就绪") {
                        Text("已生成 \(directory.manifest.cards.count) 张卡片").accessibilityIdentifier("share.catalog.ready")
                        let fallback = directory.manifest.cards.filter(\.usedFallbackIcon).count
                        if fallback > 0 { Text("\(fallback) 张卡片使用了备用图标。") }
                        if !directory.manifest.failures.isEmpty { Text("\(directory.manifest.failures.count) 个应用未完整导出，详情见导出清单。") }
                        Button("存储目录到文件") { sheet = .save(directory) }.accessibilityIdentifier("share.catalog.save")
                    }
                }
                if saved { Section { Label("目录已存储", systemImage: "checkmark.circle") } }
                if let issue { Section { Text(issue).foregroundStyle(.secondary).accessibilityIdentifier("share.catalog.error") } }
            }
            .navigationTitle("分享卡目录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { request = nil; directory?.discard(); directory = nil; dismiss() }
                }
            }
            .task(id: request) { await perform(request) }
            .onDisappear {
                // A child preview/picker still owns the staging data while open.
                if sheet == nil { directory?.discard(); directory = nil }
            }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .preview(let app): ApplicationShareView(application: app, accessibilityPrefix: "share.catalog.application")
                case .save(let directory):
                    ApplicationShareDirectoryPicker(directory: directory) { success in
                        if success { saved = true; self.directory = nil }
                        sheet = nil
                    }
                }
            }
        }
    }

    private func start(_ operation: Operation) {
        directory?.discard()
        busy = true; issue = nil; saved = false; completed = 0; total = 0; directory = nil
        request = Request(operation: operation, slug: slug.trimmingCharacters(in: .whitespacesAndNewlines),
                          wholeCatalog: wholeCatalog, styles: style.appearances)
    }

    private func perform(_ request: Request?) async {
        guard let request else { busy = false; return }
        do {
            switch request.operation {
            case .preview:
                let app = try await exporter.application(slug: request.slug)
                try Task.checkCancellation()
                guard self.request?.id == request.id else { return }
                sheet = .preview(app)
            case .export:
                let result = try await exporter.directory(slugs: request.wholeCatalog ? nil : [request.slug], appearances: request.styles) { done, count, key in
                    guard self.request?.id == request.id else { return }
                    completed = done; total = count; current = key
                }
                try Task.checkCancellation()
                guard self.request?.id == request.id else { return }
                directory = result
            }
        } catch is CancellationError { }
        catch { if self.request?.id == request.id { issue = error.localizedDescription } }
        if self.request?.id == request.id { busy = false }
    }

    private enum ExportStyle: String, CaseIterable, Identifiable {
        case dark, light, both
        var id: Self { self }
        var title: String { switch self { case .dark: return "深色"; case .light: return "浅色"; case .both: return "深浅两套" } }
        var appearances: [ApplicationShareAppearance] { switch self { case .dark: return [.dark]; case .light: return [.light]; case .both: return [.light, .dark] } }
    }
    private enum Operation: Hashable { case preview, export }
    private struct Request: Hashable {
        let id = UUID()
        let operation: Operation
        let slug: String
        let wholeCatalog: Bool
        let styles: [ApplicationShareAppearance]
    }
    private enum Sheet: Identifiable {
        case preview(CloudApplication), save(ApplicationShareExportDirectory)
        var id: String {
            switch self { case .preview(let app): return "preview-" + app.id; case .save(let directory): return directory.id.uuidString }
        }
    }
}

private struct ApplicationShareDirectoryPicker: UIViewControllerRepresentable {
    let directory: ApplicationShareExportDirectory
    let completion: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(owner: self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [directory.url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let owner: ApplicationShareDirectoryPicker
        init(owner: ApplicationShareDirectoryPicker) { self.owner = owner }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if !urls.isEmpty { owner.directory.discard() }
            owner.completion(!urls.isEmpty)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { owner.completion(false) }
    }
}
