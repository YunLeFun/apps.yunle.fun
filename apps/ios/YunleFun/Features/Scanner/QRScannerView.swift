import PhotosUI
import SafariServices
import SwiftUI

struct QRScannerView: View {
    let purpose: ScanPurpose
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            QRScannerContent(purpose: purpose)
                .navigationDestination(for: NativeDestination.self) { NativeDestinationView(destination: $0) }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        }
    }
}
private struct QRScannerContent: View {
    let purpose: ScanPurpose
    @StateObject private var model: QRScannerModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var pickingPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var website: ScanWebsite?
    @AccessibilityFocusState private var resultFocused: Bool
    init(purpose: ScanPurpose) {
        self.purpose = purpose; _model = StateObject(wrappedValue: QRScannerModel(purpose: purpose))
    }
    var body: some View {
        List {
            Section {
                if model.cameraState == .running {
                    CameraPreview(session: model.session).frame(height: 280).clipped().accessibilityHidden(true)
                        .listRowInsets(EdgeInsets())
                } else { cameraStatus }
            } footer: { Text(purpose == .workshop ? "将工坊二维码放入画面，或从相册选择二维码图片。" : "扫描应用、工坊或其他二维码。识别后可选择打开或查看内容。") }
            if model.isReadingPhoto { Section { ProgressView("正在识别图片").accessibilityIdentifier("scanner.photo.progress") } }
            if let issue = model.issue {
                Section { Label(issue, systemImage: "exclamationmark.triangle").accessibilityFocused($resultFocused) }
            }
            if !model.candidates.isEmpty {
                Section(model.candidates.count > 1 ? "识别到多个二维码，请选择" : "识别结果") {
                    ForEach(model.candidates) { candidate in result(candidate) }
                }.accessibilityFocused($resultFocused)
                Section { Button("继续扫描") { model.continueScanning() }.accessibilityIdentifier("scanner.continue") }
            }
            Section {
                Button { photoItem = nil; model.pickerIsPresented(true); pickingPhoto = true } label: { Label("从相册选择", systemImage: "photo.on.rectangle") }
                    .disabled(model.isReadingPhoto).accessibilityIdentifier("scanner.photos")
                if model.torchAvailable {
                    Button { model.toggleTorch() } label: { Label(model.torchOn ? "关闭手电筒" : "打开手电筒", systemImage: model.torchOn ? "flashlight.on.fill" : "flashlight.off.fill") }
                        .accessibilityIdentifier("scanner.torch")
                }
                NavigationLink { WorkshopLookupView() } label: { Label("输入工坊编号或链接", systemImage: "number") }
            }
        }
        .navigationTitle(purpose == .workshop ? "扫描工坊二维码" : "扫一扫").navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: $pickingPhoto, selection: $photoItem, matching: .images, preferredItemEncoding: .current)
        .onChange(of: pickingPhoto) { presented in
            if !presented && photoItem == nil { model.pickerCancelled() }
        }
        .onChange(of: photoItem) { selected in
            guard let selected else { return }
            model.readPhoto {
                guard let data = try await selected.loadTransferable(type: Data.self) else { throw ScanImageError.invalidImage }
                return data
            }
        }
        .sheet(item: $website) { SafariView(url: $0.url) }
        .onAppear { model.sceneIsActive(scenePhase == .active); model.appear() }
        .onDisappear { model.disappear() }
        .onChange(of: scenePhase) { model.sceneIsActive($0 == .active) }
        .onChange(of: model.candidates) { if !$0.isEmpty { resultFocused = true } }
        .onChange(of: model.issue) { if $0 != nil { resultFocused = true } }
    }
    @ViewBuilder private var cameraStatus: some View {
        switch model.cameraState {
        case .permissionRequired:
            Label("使用相机扫描二维码", systemImage: "qrcode.viewfinder")
            Button("启用相机") { Task { await model.enableCamera() } }.accessibilityIdentifier("scanner.camera.enable")
        case .checking: ProgressView("正在准备相机")
        case .denied:
            Label("尚未允许相机访问", systemImage: "camera")
            Text("可在设置中允许相机访问，也可以从相册选择二维码。").foregroundStyle(.secondary)
            Button("前往设置") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
        case .restricted:
            Label("相机访问受到系统限制", systemImage: "camera")
            Text("你仍可以从相册识别二维码，或输入工坊编号。").foregroundStyle(.secondary)
        case .unavailable:
            Label("当前设备没有可用的相机", systemImage: "camera")
                .accessibilityIdentifier("scanner.camera.unavailable")
            Text("可以从相册识别二维码，或输入工坊编号。").foregroundStyle(.secondary)
        case .interrupted:
            Label("相机暂时被其他功能占用", systemImage: "pause.circle")
            Button("重新扫描") { model.continueScanning() }
        case .failed:
            Label("暂时无法启动相机", systemImage: "camera")
            Button("重试") { model.continueScanning() }
        case .paused:
            if model.candidates.isEmpty && !model.isReadingPhoto {
                Label("相机已暂停", systemImage: "pause.circle")
                Button("继续扫描") { model.continueScanning() }
            } else { Label("已暂停扫描", systemImage: "qrcode") }
        case .running: EmptyView()
        }
    }
    @ViewBuilder private func result(_ candidate: ScanCandidate) -> some View {
        switch candidate.result {
        case .destination(let destination):
            NavigationLink(value: destination) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(destinationLabel(destination), systemImage: "arrow.up.right")
                    Text(candidate.payload).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }.accessibilityIdentifier("scanner.result.destination")
        case .website(let url):
            VStack(alignment: .leading, spacing: 8) {
                Label(candidate.title, systemImage: "globe").font(.headline)
                Text(url.absoluteString).font(.footnote).textSelection(.enabled)
                Button("使用浏览器打开") { website = ScanWebsite(url: url) }.accessibilityIdentifier("scanner.result.website")
            }
        case .text(let text):
            VStack(alignment: .leading, spacing: 8) {
                Label("文本", systemImage: "text.alignleft").font(.headline)
                Text(text).textSelection(.enabled)
                ShareLink(item: text) { Label("分享文本", systemImage: "square.and.arrow.up") }
            }
        case .unsupportedWorkshop:
            Label("未识别到工坊链接，请扫描云乐坊个人工坊二维码。", systemImage: "exclamationmark.triangle")
        case .unsupportedLink:
            Label("无法打开此二维码中的链接。可以重新扫描其他二维码。", systemImage: "exclamationmark.triangle")
        }
    }
    private func destinationLabel(_ destination: NativeDestination) -> String {
        switch destination { case .workshop: return "打开个人工坊"; case .application: return "查看云应用" }
    }
}
private struct ScanWebsite: Identifiable { let id = UUID(); let url: URL }
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

struct NativeDestinationView: View {
    let destination: NativeDestination
    var body: some View {
        switch destination {
        case .workshop(let id): PublicWorkshopView(id: id)
        case .application(let key): LinkedApplicationView(key: key)
        }
    }
}
private struct LinkedApplicationView: View {
    let key: String
    @EnvironmentObject private var catalog: CatalogStore
    var body: some View {
        Group {
            if let app = NativeLink.publicApplication(key: key, in: catalog.applications) { ApplicationDetailView(application: app) }
            else if catalog.isLoading { ProgressView("正在载入应用") }
            else if let error = catalog.error {
                ContentStateView(title: "暂时无法载入应用", systemImage: "wifi.exclamationmark", message: error,
                                 actionTitle: "重试", action: { Task { await catalog.load() } })
            } else {
                ContentStateView(title: "未找到这个公开应用", systemImage: "square.grid.2x2", message: "应用可能已停止公开，请确认链接后再试。")
            }
        }
        .navigationTitle(NativeLink.publicApplication(key: key, in: catalog.applications)?.name ?? "云应用").navigationBarTitleDisplayMode(.inline)
        .task { await catalog.load() }
    }
}
