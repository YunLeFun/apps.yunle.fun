import SwiftUI

struct DeveloperApplicationsView: View {
    let login: String
    @StateObject private var model: DeveloperProfileStore
    @State private var returningApplicationID: String?
    @AccessibilityFocusState(for: .voiceOver) private var focusedApplicationID: String?

    init(login: String, service: DeveloperProfileServing = DeveloperProfileService()) {
        self.login = login
        _model = StateObject(wrappedValue: DeveloperProfileStore(service: service))
    }

    var body: some View {
        List {
            if model.isLoading { ProgressView("正在载入作者主页").accessibilityIdentifier("developer.loading") }
            if let error = model.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("重试") { Task { await model.refresh(login: login) } }.disabled(model.isLoading)
                }.accessibilityIdentifier("developer.error")
            }
            if let profile = model.profile {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "person.crop.circle").font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(profile.displayName).font(.title2.bold()).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                        if profile.displayName != profile.ownerLogin {
                            Text("@\(profile.ownerLogin)").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Text("\(profile.items.count) 个公开作品").foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                    Link(destination: profile.githubURL) { Label("在 GitHub 上查看", systemImage: "arrow.up.right.square") }
                }
                Section {
                    if profile.items.isEmpty {
                        ContentStateView(title: "还没有公开作品", systemImage: "square.grid.2x2",
                                         message: "作者公开发布的作品会出现在这里。")
                            .accessibilityIdentifier("developer.empty")
                    }
                    ForEach(profile.items) { app in
                        NavigationLink {
                            ApplicationDetailView(application: app)
                                .onAppear { returningApplicationID = app.id; focusedApplicationID = nil }
                        } label: { ApplicationRow(application: app) }
                        .accessibilityIdentifier("developer.application.\(app.id)")
                        .accessibilityFocused($focusedApplicationID, equals: app.id)
                    }
                } header: { Text("公开作品").foregroundStyle(Color.primary) }
                footer: { Text("展示作者当前公开发布的版本，可能与云乐坊上架版本不同。") }
            }
        }
        .navigationTitle(model.profile?.ownerLogin ?? DeveloperProfile.normalizedLogin(login) ?? "作者主页").navigationBarTitleDisplayMode(.inline)
        .runtimeMenuToolbar()
        .toolbar {
            if let profile = model.profile {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: profile.shareURL) { Label("分享作者主页", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .task(id: login) { await model.refresh(login: login) }
        .refreshable { await model.refresh(login: login) }
        .onDisappear { model.cancel() }
        .onAppear {
            if let returningApplicationID { focusedApplicationID = returningApplicationID; self.returningApplicationID = nil }
        }
    }
}
