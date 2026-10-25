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
            HomeView { selectedTab = .workshop }
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
