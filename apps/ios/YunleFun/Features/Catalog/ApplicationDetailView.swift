import SwiftUI

struct ApplicationDetailView: View {
    let application: CloudApplication
    @Environment(\.runtimeMenu) private var runtimeMenu
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var runtime: NativeWebRuntime
    @EnvironmentObject private var accounts: AccountStore
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
                HStack(alignment: .top, spacing: 16) {
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
            if app.accessWorkshopID == nil && app.accessOwnerID == nil {
                Section { NavigationLink("评分与评价") { ApplicationReviewsView(application: app) } }
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
                ShareLink(item: app.accessWorkshopID.map { CatalogService.productionOrigin.appendingPathComponent("w/\($0)") } ?? CatalogService.productionOrigin.appendingPathComponent("app/\(app.publicKey)")) {
                    Label("分享应用", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    @ViewBuilder private var action: some View {
        if let menu = runtimeMenu, menu.applicationID == app.id {
            Button("返回应用", action: menu.dismiss).buttonStyle(.borderedProminent)
        } else if let condition = app.accessOwnerID != nil ? app.ownerPreviewRestriction : (app.accessWorkshopID != nil ? app.launchRestriction : (app.isUnavailable == true ? app.launchRestriction : nil)) {
            Label(condition, systemImage: "lock").font(.subheadline).foregroundStyle(.secondary)
        } else if app.launchURL == nil {
            Text("暂时无法打开").font(.subheadline).foregroundStyle(.secondary)
        } else {
            HStack {
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
    }
}
