import SwiftUI

/// Every icon observes the same manifest, so an update also refreshes already visible rows and details.
struct CatalogApplicationIconImage<Fallback: View>: View {
    let application: CloudApplication
    let pixelSize: Int
    var pipeline: ApplicationImagePipeline = .shared
    @ObservedObject var catalog: CatalogIconStore = .shared
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var fallback: () -> Fallback

    var body: some View {
        ApplicationIconImage(candidates: application.iconCandidates(dark: colorScheme == .dark, downloaded: catalog.assets, websites: catalog.websiteIcons),
                             pixelSize: pixelSize, pipeline: pipeline, isUnavailable: application.isUnavailable == true, fallback: fallback)
    }
}

struct CatalogIconUpdates: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content.task(id: scenePhase) {
            guard scenePhase == .active,
                  ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
                  Bundle.main.bundleIdentifier?.hasSuffix(".tests-host") != true else { return }
            await CatalogIconStore.shared.refreshWhileActive()
        }
    }
}

struct ApplicationIconImage<Fallback: View>: View {
    let candidates: [ApplicationIconCandidate]
    let pixelSize: Int
    var pipeline: ApplicationImagePipeline = .shared
    var isUnavailable = false
    @ViewBuilder var fallback: () -> Fallback
    @State private var loaded: LoadedApplicationIcon?
    @State private var loadedKey: Request?
    @State private var finishedKey: Request?
    private struct Request: Hashable { let candidates: [ApplicationIconCandidate]; let pixels: Int }
    private var key: Request { Request(candidates: candidates, pixels: pixelSize) }
    private var displayedIcon: LoadedApplicationIcon? {
        if let loaded, loadedKey == key { return loaded }
        if let loaded, candidates.contains(where: { $0.url == loaded.candidate.url && $0.role == loaded.candidate.role }) { return loaded }
        return pipeline.cachedIcon(candidates, pixelSize: pixelSize)
    }
    private var placeholderFill: Color {
        #if os(macOS)
        Color(nsColor: .quaternaryLabelColor)
        #else
        Color(uiColor: .tertiarySystemFill)
        #endif
    }
    var body: some View {
        Group {
            if let loaded = displayedIcon {
                Image(decorative: loaded.bitmap.image, scale: 1)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(loaded.candidate.role == .appIcon ? Color.clear : placeholderFill)
                    .modifier(ApplicationIconAvailabilityStyle(isUnavailable: isUnavailable))
            } else if !candidates.isEmpty && finishedKey != key {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(placeholderFill)
            } else { fallback() }
        }
        .task(id: key) {
            let request = key
            // SwiftUI restarts this task on reappearance, even for the same key.
            // Keep already displayed artwork while resolving the current request.
            let started = Date()
            do {
                if let cached = try await pipeline.cachedIconFromDisk(request.candidates, pixelSize: request.pixels) {
                    try Task.checkCancellation()
                    loaded = cached; loadedKey = request
                }
                let value = try await pipeline.load(request.candidates, pixelSize: request.pixels)
                try Task.checkCancellation()
                // Memory-cache hits swap instantly so revisited screens don't
                // flicker; only real network / decode waits fade in.
                withAnimation(Date().timeIntervalSince(started) > 0.08 ? .easeInOut(duration: 0.15) : nil) {
                    loaded = value; loadedKey = request; finishedKey = request
                }
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled else { return }
                if loadedKey != request { loaded = nil; loadedKey = request }
                finishedKey = request
            }
        }
    }
}

/// Decorates actual artwork only. A missing image keeps its plain dashed placeholder.
struct ApplicationIconAvailabilityStyle: ViewModifier {
    let isUnavailable: Bool
    func body(content: Content) -> some View {
        content
            .saturation(isUnavailable ? 0 : 1)
            .opacity(isUnavailable ? 0.55 : 1)
            .overlay {
                if isUnavailable {
                    GeometryReader { proxy in
                        let size = min(proxy.size.width, proxy.size.height)
                        Image(systemName: "nosign")
                            .resizable().scaledToFit()
                            .foregroundStyle(.secondary)
                            .padding(size * 0.025)
                            .frame(width: size * 0.3, height: size * 0.3)
                            .background(.background, in: Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(size * 0.05)
                    }
                }
            }
    }
}
