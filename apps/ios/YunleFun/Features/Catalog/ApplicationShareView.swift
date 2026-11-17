import SwiftUI

@MainActor
struct ApplicationShareView: View {
    let application: CloudApplication
    var accessibilityPrefix = "application.share"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearance: ApplicationShareAppearance?
    @State private var card: UIImage?
    @State private var issue: String?
    @State private var iconUnavailable = false
    @State private var activity: ApplicationShareActivity?
    @State private var retry = 0
    @State private var catalogExport = false
    private var selected: ApplicationShareAppearance { appearance ?? (colorScheme == .dark ? .dark : .light) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("卡片外观", selection: Binding(get: { selected }, set: { appearance = $0 })) {
                        ForEach(ApplicationShareAppearance.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier(accessibilityPrefix + ".appearance")
                    preview
                    if iconUnavailable {
                        Text("应用未提供可用图标，卡片使用备用图标。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("重新加载图标") { retry += 1 }
                    }
                    actions
                    Text("二维码打开应用网站；分享链接可在云乐坊中查看，或进入网页详情。")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 420).padding(20).frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("分享应用").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { catalogExport = true } label: { Label("分享卡目录", systemImage: "folder") }
                        .accessibilityIdentifier(accessibilityPrefix + ".catalog")
                }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .task(id: "\(selected.rawValue)-\(retry)") { await prepare() }
            .sheet(item: $activity) { ApplicationShareActivityView(image: $0.image) }
            .sheet(isPresented: $catalogExport) { ApplicationShareCatalogView(slug: application.publicKey, appearance: selected) }
        }
    }

    @ViewBuilder private var preview: some View {
        if let card {
            Image(uiImage: card).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.06), lineWidth: 0.5) }
                .accessibilityLabel("\(application.name)，\(application.summary)，\(selected.title)分享卡片，含网站二维码")
                .accessibilityIdentifier(accessibilityPrefix + ".preview")
        } else if let issue {
            ContentStateView(title: "卡片暂不可用", systemImage: "qrcode", message: issue,
                             actionTitle: "重试", action: { retry += 1 })
        } else {
            ProgressView("正在生成分享卡片").frame(height: 300).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var actions: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 12) { actionButtons }
        } else { actionButtons }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button { if let card { activity = ApplicationShareActivity(image: card) } } label: {
                Label("分享或存储卡片", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .modifier(ApplicationShareButtonStyle(prominent: true)).disabled(card == nil)
            .accessibilityIdentifier(accessibilityPrefix + ".image")
            ShareLink(item: application.shareURL) {
                Label("分享应用链接", systemImage: "link").frame(maxWidth: .infinity)
            }
            .modifier(ApplicationShareButtonStyle(prominent: false))
            .accessibilityIdentifier(accessibilityPrefix + ".link")
        }
    }

    @MainActor private func prepare() async {
        let target = selected
        card = nil; issue = nil; iconUnavailable = false
        do {
            let result = try await ApplicationShareExporter().render(application, appearance: target)
            try Task.checkCancellation()
            iconUnavailable = result.usedFallbackIcon
            card = result.image
        } catch is CancellationError { return }
        catch { issue = error.localizedDescription }
    }
}

private struct ApplicationShareActivity: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ApplicationShareActivityView: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct ApplicationShareButtonStyle: ViewModifier {
    let prominent: Bool
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26, *) {
                if prominent { content.buttonStyle(.glassProminent) }
                else { content.buttonStyle(.glass) }
            } else {
                if prominent { content.buttonStyle(.borderedProminent) }
                else { content.buttonStyle(.bordered) }
            }
        }.controlSize(.large).buttonBorderShape(.capsule)
    }
}
