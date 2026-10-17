import SwiftUI

struct ApplicationDetailView: View {
    let application: CloudApplication
    @Environment(\.runtimeMenu) private var runtimeMenu
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var runtime: NativeWebRuntime
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var workshopIdentity: UUID?
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 12)
            }
            Section("关于这个应用") { Text(app.summary).textSelection(.enabled) }
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
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(screenshots, id: \.self) { value in
                                if let url = URL(string: value), url.scheme == "https" {
                                    AsyncImage(url: url) { image in image.resizable().scaledToFit() }
                                    placeholder: { ProgressView() }
                                    .frame(height: 280)
                                    .accessibilityLabel("\(app.name)的应用预览")
                                }
                            }
                        }
                    }
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
            Button("返回应用", action: menu.dismiss).buttonStyle(.borderedProminent)
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
                .buttonStyle(.borderedProminent)
        } else {
            Button("获取") {
                if app.canOpenAsGuest || app.accessWorkshopID != nil || app.accessOwnerID != nil { library.add(app) }
                else { runtime.acquire(app, intent: .install, catalog: catalog, library: library) }
            }.buttonStyle(.borderedProminent)
        }
        if !library.contains(app) && runtime.verifyingScopedApplicationID != app.id && (app.canOpenAsGuest || app.accessWorkshopID != nil || app.accessOwnerID != nil) {
            Button("试用") { runtime.open(app, catalog: catalog, library: library) }.buttonStyle(.bordered)
        }
    }
}
