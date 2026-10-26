import SwiftUI

struct AppRootView: View {
    @State private var selectedTab = AppTab.home
    @State private var workshopPath = NavigationPath()
    @StateObject private var feedbackLogin = FeedbackLoginCoordinator()
    @StateObject private var crossAppAuthorization = CrossAppAuthorizationCoordinator()
    @StateObject private var screenshotFeedback = ScreenshotFeedbackCoordinator()
    @AppStorage(ScreenshotFeedbackPromptState.preferenceKey) private var screenshotFeedbackEnabled = true
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var runtime: NativeWebRuntime
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var diagnostics: DiagnosticLogStore

    var body: some View {
        tabs
            .environment(\.screenshotFeedbackCoordinator, screenshotFeedback)
            .environment(\.requestFeedbackLogin, { text in
                feedbackLogin.begin(text: text, origin: accountBoundary, isRestoring: accounts.isRestoring)
            })
            .background(RuntimePresentationAnchor(runtime: runtime, catalog: catalog, library: library).frame(width: 0, height: 0))
            .background(ScreenshotFeedbackAnchor(coordinator: screenshotFeedback, enabled: screenshotFeedbackEnabled,
                logs: diagnostics, accounts: accounts, requestLogin: { [feedbackLogin, accounts] text in
                    feedbackLogin.begin(text: text, origin: .init(uid: accounts.user?.id, generation: accounts.identityGeneration),
                                        isRestoring: accounts.isRestoring)
                }).frame(width: 0, height: 0))
            .onOpenURL(perform: handleLink)
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { handleLink(url) }
            }
            .alert(item: $runtime.issue) { issue in
                Alert(title: Text(issue.title), message: Text(issue.message), dismissButton: .default(Text("好")))
            }
            .sheet(item: $runtime.unavailableApplication) { application in
                ApplicationUnavailableView(application: application).environmentObject(library)
            }
            .background(EmptyView().alert(item: $crossAppAuthorization.issue) { issue in
                Alert(title: Text(issue.title), message: Text(issue.message), dismissButton: .default(Text("好")))
            })
            .sheet(item: Binding(get: { feedbackLogin.login }, set: { if $0 == nil { feedbackLogin.presentationEnded() } }),
                   onDismiss: {
                if feedbackLogin.didDismiss(current: accountBoundary, isUsable: accounts.user?.isUsable == true,
                                            proofIsCurrent: continuationIsCurrent) {
                    selectedTab = .me
                }
                screenshotFeedback.loginDidDismiss()
            }) { intent in
                LoginView(continuationMessage: "登录后返回反馈与建议，并保留问题描述。上传前仍需重新预览并确认。",
                          continuation: intent.continuation,
                          onCommitted: { success in
                    feedbackLogin.committed(success, current: accountBoundary, isUsable: accounts.user?.isUsable == true,
                                            proofIsCurrent: accounts.isCurrent(success))
                }, onCancelled: { feedbackLogin.cancel() })
                .environmentObject(accounts)
                .onAppear { feedbackLogin.didPresent(intent.id) }
            }
            .onChange(of: accounts.identityGeneration) { _ in
                screenshotFeedback.discard()
                screenshotFeedback.cancelPendingLogin()
                updateFeedbackIdentity()
            }
            .onChange(of: accounts.selectionOperationGeneration) { _ in updateFeedbackIdentity() }
    }

    @ViewBuilder private var tabs: some View {
        if #available(iOS 18, *) {
            TabView(selection: $selectedTab) {
                Tab("云居", systemImage: "house", value: AppTab.home) { home }
                Tab("寻乐", systemImage: "safari", value: AppTab.discovery) { discovery }
                Tab("工坊", systemImage: "square.grid.2x2", value: AppTab.workshop) { workshop }
                Tab("我", systemImage: "person.crop.circle", value: AppTab.me) { me }
            }
        } else {
            TabView(selection: $selectedTab) {
                home.tabItem { Label("云居", systemImage: "house") }.tag(AppTab.home)
                discovery.tabItem { Label("寻乐", systemImage: "safari") }.tag(AppTab.discovery)
                workshop.tabItem { Label("工坊", systemImage: "square.grid.2x2") }.tag(AppTab.workshop)
                me.tabItem { Label("我", systemImage: "person.crop.circle") }.tag(AppTab.me)
            }
        }
    }

    private var home: some View {
        NavigationStack {
            HomeWorkspaceView(accounts: accounts) { selectedTab = .workshop }
                .id(accounts.identityGeneration)
                .navigationDestination(for: CloudApplication.self) { ApplicationDetailView(application: $0) }
        }
    }
    private var discovery: some View {
        NavigationStack {
            DiscoveryView()
                .navigationDestination(for: CloudApplication.self) { ApplicationDetailView(application: $0) }
        }
    }
    private var workshop: some View {
        NavigationStack(path: $workshopPath) {
            CatalogView()
                .navigationDestination(for: CloudApplication.self) { ApplicationDetailView(application: $0) }
                .navigationDestination(for: NativeDestination.self) { NativeDestinationView(destination: $0) }
        }
    }
    private func handleLink(_ url: URL) {
        // 跨 App 授权入口优先：只弹授权面板，不切换 Tab、不打断当前页面
        if crossAppAuthorization.handle(url, runtime: runtime, accounts: accounts) {
            screenshotFeedback.cancelPendingLogin()
            return
        }
        // Authentication callbacks belong to ASWebAuthenticationSession, never
        // to the navigation parser. No raw callback URL is stored or logged.
        guard let destination = NativeLink.destination(url) else { return }
        screenshotFeedback.cancelPendingLogin()
        feedbackLogin.cancel()
        selectedTab = .workshop
        workshopPath.append(destination)
    }
    private var me: some View {
        let stackBoundary = accountBoundary
        return NavigationStack(path: Binding(
            get: {
                guard stackBoundary == accountBoundary else { return [] }
                return feedbackLogin.path(current: accountBoundary, isUsable: accounts.user?.isUsable == true,
                                          proofIsCurrent: continuationIsCurrent)
            },
            set: { feedbackLogin.updatePath($0, stack: stackBoundary, current: accountBoundary,
                                            isUsable: accounts.user?.isUsable == true, proofIsCurrent: continuationIsCurrent) })) {
            MeView(navigateTab: { selectedTab = $0 })
                .navigationDestination(for: FeedbackResumeRoute.self) { route in
                    if let text = feedbackLogin.text(for: route, current: accountBoundary, isUsable: accounts.user?.isUsable == true,
                                                     proofIsCurrent: continuationIsCurrent) {
                        FeedbackView(logs: diagnostics, accounts: accounts, initialIssueDescription: text).id(route.id)
                    }
                }
        }.id(accounts.identityGeneration)
    }
    private var accountBoundary: AccountRequestBoundary {
        .init(uid: accounts.user?.id, generation: accounts.identityGeneration)
    }
    private var continuationIsCurrent: Bool { feedbackLogin.success.map { accounts.isCurrent($0) } ?? false }
    private func updateFeedbackIdentity() {
        feedbackLogin.identityChanged(to: accountBoundary, isUsable: accounts.user?.isUsable == true,
                                      proofIsCurrent: continuationIsCurrent)
    }
}

/// Checking status preserves the installation; removal is an explicit confirmed action.
struct ApplicationUnavailableView: View {
    let application: CloudApplication
    var service: ApplicationAvailabilityServing = CatalogService()
    @EnvironmentObject private var library: HomeLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var refreshID = UUID()
    @State private var phase = Phase.checking
    @State private var confirmsRemoval = false
    @State private var removalGeneration: UUID?

    private enum Phase {
        case checking, unavailable(ApplicationUnavailableReason), available, failed
    }

    private var isChecking: Bool { if case .checking = phase { return true }; return false }
    private var isInHome: Bool {
        let configuration = library.snapshot.configuration
        return configuration.installedApps.contains { $0.appId == application.homeKey }
            || configuration.dockApps.contains { $0.appId == application.homeKey }
            || configuration.recentApps.contains { $0.appId == application.homeKey }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        ApplicationIcon(application: application)
                        Text(application.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section {
                    switch phase {
                    case .checking:
                        ProgressView("正在确认应用状态")
                    case .unavailable(let reason):
                        Label(reason.title, systemImage: "info.circle").font(.headline)
                        Text(reason.message).fixedSize(horizontal: false, vertical: true)
                    case .available:
                        Label("应用已恢复可用", systemImage: "checkmark.circle").font(.headline)
                        Text("应用资料已更新，可以返回云居重新打开。")
                    case .failed:
                        Label("暂时无法确认应用状态", systemImage: "wifi.exclamationmark").font(.headline)
                        Text("无法连接应用服务。请检查网络后重试，云居中的安装记录和缓存已保留。")
                    }
                }
                Section {
                    Button { refreshID = UUID() } label: { Label("刷新状态", systemImage: "arrow.clockwise") }
                        .disabled(isChecking)
                        .accessibilityIdentifier("application.availability.refresh")
                }
                Section {
                    Button(role: .destructive) { confirmsRemoval = true } label: {
                        Label("从云居移除", systemImage: "minus.circle")
                    }
                    .disabled(!isInHome)
                    .accessibilityIdentifier("application.availability.remove")
                    if let error = library.storageError { Text(error).foregroundStyle(.red) }
                } footer: {
                    Text("仅移除云居记录，不会删除应用本身或缓存。")
                }
            }
            .navigationTitle("应用状态")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .onAppear { if removalGeneration == nil { removalGeneration = library.generation } }
            .confirmationDialog("从云居移除此应用？", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button("从云居移除", role: .destructive, action: removeFromHome)
                Button("取消", role: .cancel) { }
            } message: {
                Text("会从云居、常用应用和最近使用中移除，应用本身和缓存仍会保留。")
            }
            .task(id: refreshID) { await refresh() }
            .accessibilityIdentifier("application.availability")
        }
    }

    private func removeFromHome() {
        guard removalGeneration == library.generation else { dismiss(); return }
        library.remove(application)
        if !isInHome { dismiss() }
    }

    private func refresh() async {
        let generation = library.generation
        phase = .checking
        do {
            let current = try await service.application(reference: application.homeKey)
            try Task.checkCancellation()
            guard library.generation == generation else { return }
            library.updateCatalog([current])
            phase = .available
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled, library.generation == generation else { return }
            if let reason = error as? ApplicationUnavailableReason { phase = .unavailable(reason) }
            else { phase = .failed }
        }
    }
}
