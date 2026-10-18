import SwiftUI

struct ApplicationDetailView: View {
    let application: CloudApplication
    @Environment(\.runtimeMenu) private var runtimeMenu
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var runtime: NativeWebRuntime
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var workshopIdentity: UUID?
    /// Set when this visit added the app, so the header confirms where it went.
    @State private var addedHere = false
    private var app: CloudApplication { application.refreshingPublicMetadata(with: catalog.application(id: application.id)) }

    var body: some View {
        Group {
            if (application.accessWorkshopID == nil && application.accessOwnerID == nil) || workshopIdentity == accounts.identityGeneration { content }
            else if workshopIdentity == nil { ProgressView("正在确认账号") }
            else { ContentStateView(title: "账号已变化", systemImage: "person.crop.circle", message: "请返回工坊重新打开应用详情。").navigationTitle("工坊应用") }
        }
        .onAppear { if workshopIdentity == nil { workshopIdentity = accounts.identityGeneration } }
        .runtimeMenuToolbar()
    }

    private var content: some View {
        List {
            Section {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                layout {
                    ApplicationIcon(application: app, size: 84)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.name).font(.title2.bold())
                        Text(app.author).font(.subheadline).foregroundStyle(.secondary)
                        action
                        if addedHere && library.contains(app) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
                                Text("已加入云居").foregroundStyle(.secondary)
                            }
                            .font(.footnote)
                            .accessibilityElement(children: .combine)
                            .transition(.opacity)
                            .accessibilityIdentifier("detail.added")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(Motion.standard(reduceMotion: reduceMotion), value: library.contains(app))
                    .animation(Motion.fade, value: runtime.verifyingScopedApplicationID)
                }
                .padding(.vertical, 12)
                .haptic(.success, trigger: library.contains(app)) { old, new in !old && new }
            }
            Section("关于这个应用") { Text(app.summary).textSelection(.enabled) }
            if #available(iOS 17, *) {
                Section {
                    NavigationLink {
                        WebProfileRecoveryView(application: app)
                    } label: { Label("应用数据", systemImage: "archivebox") }
                    .accessibilityIdentifier("detail.web-profiles")
                }
            }
            if app.accessWorkshopID == nil && app.accessOwnerID == nil && app.personalMarketOwnerLogin == nil {
                Section { NavigationLink("评分与评价") { ApplicationReviewsView(application: app) } }
            }
            if app.personalMarketOwnerLogin != nil {
                Section {
                    Label("作者公开发布的版本", systemImage: "person.crop.circle")
                    Text("此版本可能与云乐坊上架版本不同。").foregroundStyle(.secondary)
                    if let marketVersion = catalog.applications.first(where: { $0.id == app.id }) {
                        NavigationLink("查看云乐坊版本") { ApplicationDetailView(application: marketVersion) }
                    }
                }
            }
            Section {
                NavigationLink {
                    ApplicationCacheView(application: app, store: runtime.applicationCache)
                } label: { Label("应用下载缓存", systemImage: "arrow.down.circle") }
            }
            Section("信息") {
                LabeledContent("分类", value: app.browseCategory)
                LabeledContent("开发者", value: app.author)
                if app.isOfficial == true { Label("云乐坊官方应用", systemImage: "checkmark.seal") }
                if let host = app.launchURL?.host { LabeledContent("网站", value: host) }
                if let count = app.ratingCount, let rating = app.displayRating {
                    LabeledContent("评分", value: String(format: "%.1f · %d 个评价", rating, count))
                }
                if let label = app.accessLabel { LabeledContent("使用条件", value: label) }
            }
            if let screenshots = app.screenshots, !screenshots.isEmpty {
                Section("应用预览") {
                    ScreenshotStrip(name: app.name, screenshots: screenshots)
                        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                }
            }
            if let issue = library.storageError {
                Section { Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) }
            }
            if library.contains(app) {
                Section {
                    Button("从云居移除", role: .destructive) { library.remove(app) }
                }
            }
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: app.shareURL) {
                    Label(app.personalMarketOwnerLogin == nil ? "分享应用" : "分享作者主页", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    @ViewBuilder private var action: some View {
        if let menu = runtimeMenu, menu.represents(app) {
            Button("返回应用", action: menu.dismiss).buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        } else if app.personalMarketOwnerLogin != nil && !app.canOpenAsGuest {
            VStack(alignment: .leading, spacing: 6) {
                Label(app.accessLabel ?? "暂时无法打开", systemImage: "lock").font(.subheadline)
                if app.launchRestriction != nil {
                    Text("作者版本的使用权限需要进一步确认。可查看云乐坊版本或联系作者。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        } else if let condition = app.accessOwnerID != nil ? app.ownerPreviewRestriction : (app.accessWorkshopID != nil ? app.launchRestriction : (app.isUnavailable == true ? app.launchRestriction : nil)) {
            Label(condition, systemImage: "lock").font(.subheadline).foregroundStyle(.secondary)
        } else if app.launchURL == nil {
            Text("暂时无法打开").font(.subheadline).foregroundStyle(.secondary)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack { acquisitionActions }
                VStack(alignment: .leading) { acquisitionActions }
            }
        }
    }

    @ViewBuilder private var acquisitionActions: some View {
        if runtime.verifyingScopedApplicationID == app.id { ProgressView("正在确认访问权限") }
        else if library.contains(app) {
            Button("打开") { runtime.open(app, catalog: catalog, library: library) }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        } else {
            Button("获取") {
                if app.canOpenAsGuest || app.accessWorkshopID != nil || app.accessOwnerID != nil { addedHere = true; library.add(app) }
                else { addedHere = true; runtime.acquire(app, intent: .install, catalog: catalog, library: library) }
            }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
        if !library.contains(app) && runtime.verifyingScopedApplicationID != app.id && (app.canOpenAsGuest || app.accessWorkshopID != nil || app.accessOwnerID != nil) {
            Button("试用") { runtime.open(app, catalog: catalog, library: library) }.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }
}

/// Horizontally paged previews with rounded corners, a hairline edge so light
/// screenshots don't bleed into the background, and a fade-in once loaded.
private struct ScreenshotStrip: View {
    let name: String
    let screenshots: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(screenshots, id: \.self) { value in
                    if let url = URL(string: value), url.scheme == "https" {
                        AsyncImage(url: url, transaction: Transaction(animation: Motion.fade)) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFit().transition(.opacity)
                            case .failure: Image(systemName: "photo").foregroundStyle(.secondary).frame(width: 160)
                            default: Color(uiColor: .tertiarySystemFill).frame(width: 160).overlay(ProgressView())
                            }
                        }
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.quaternary, lineWidth: 0.5))
                        .accessibilityLabel("\(name)的应用预览")
                    }
                }
            }
            .padding(.horizontal, 20)
            .modifier(ScrollTargetLayout())
        }
        .modifier(ViewAlignedPaging())
    }
}

private struct ScrollTargetLayout: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17, *) { content.scrollTargetLayout() } else { content }
    }
}

private struct ViewAlignedPaging: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17, *) { content.scrollTargetBehavior(.viewAligned) } else { content }
    }
}
