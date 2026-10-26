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
                             pixelSize: pixelSize, pipeline: pipeline, fallback: fallback)
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
    @ViewBuilder var fallback: () -> Fallback
    @State private var loaded: LoadedApplicationIcon?
    @State private var loadedKey: Request?
    @State private var finishedKey: Request?
    private struct Request: Hashable { let candidates: [ApplicationIconCandidate]; let pixels: Int }
    private var key: Request { Request(candidates: candidates, pixels: pixelSize) }
    private var placeholderFill: Color {
        #if os(macOS)
        Color(nsColor: .quaternaryLabelColor)
        #else
        Color(uiColor: .tertiarySystemFill)
        #endif
    }
    var body: some View {
        Group {
            if let loaded, loadedKey == key {
                Image(decorative: loaded.bitmap.image, scale: 1)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(loaded.candidate.role == .appIcon ? Color.clear : placeholderFill)
            } else if !candidates.isEmpty && finishedKey != key {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(placeholderFill)
            } else { fallback() }
        }
        .task(id: key) {
            let request = key
            loaded = nil; loadedKey = nil; finishedKey = nil
            let started = Date()
            do {
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
                loaded = nil; loadedKey = request; finishedKey = request
            }
        }
    }
}
