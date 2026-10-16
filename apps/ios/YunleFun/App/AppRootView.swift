import SwiftUI

struct AppRootView: View {
    @State private var selectedTab = AppTab.home
    @State private var workshopPath = NavigationPath()
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var runtime: NativeWebRuntime
    @EnvironmentObject private var accounts: AccountStore

    var body: some View {
        tabs
            .background(RuntimePresentationAnchor(runtime: runtime, catalog: catalog, library: library).frame(width: 0, height: 0))
            .onOpenURL(perform: handleLink)
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { handleLink(url) }
            }
            .alert(item: $runtime.issue) { issue in
                Alert(title: Text(issue.title), message: Text(issue.message), dismissButton: .default(Text("好")))
            }
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
        // Authentication callbacks belong to ASWebAuthenticationSession, never
        // to the navigation parser. No raw callback URL is stored or logged.
        guard let destination = NativeLink.destination(url) else { return }
        selectedTab = .workshop
        workshopPath.append(destination)
    }
    private var me: some View { NavigationStack { MeView() }.id(accounts.identityGeneration) }
}
