import SwiftUI

struct ApplicationIcon: View {
    let application: CloudApplication
    var size: CGFloat = 52
    var pipeline: ApplicationImagePipeline = .shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            ApplicationIconImage(candidates: application.iconCandidates(dark: colorScheme == .dark),
                                 size: size, pixelSize: Int((size * displayScale).rounded(.up)), pipeline: pipeline) { fallback }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        ZStack {
            Color(uiColor: .tertiarySystemFill)
            Text(application.emoji?.nilIfEmpty ?? String(application.name.prefix(1)))
                .font(.system(size: size * 0.48, weight: .medium))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.5)
        }
    }
}

private struct ApplicationIconImage<Fallback: View>: View {
    let candidates: [ApplicationIconCandidate]
    let size: CGFloat
    let pixelSize: Int
    var pipeline: ApplicationImagePipeline = .shared
    @ViewBuilder var fallback: () -> Fallback
    @State private var loaded: LoadedApplicationIcon?
    @State private var loadedKey: Request?
    private struct Request: Hashable { let candidates: [ApplicationIconCandidate]; let pixels: Int }
    private var key: Request { Request(candidates: candidates, pixels: pixelSize) }
    var body: some View {
        Group {
            if let loaded, loadedKey == key {
                Image(uiImage: UIImage(cgImage: loaded.bitmap.image))
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(loaded.candidate.role == .appIcon ? Color.clear : Color(uiColor: .tertiarySystemFill))
            } else { fallback() }
        }
        .task(id: key) {
            let request = key
            loaded = nil; loadedKey = nil
            do {
                let value = try await pipeline.load(request.candidates, pixelSize: request.pixels)
                try Task.checkCancellation()
                loaded = value; loadedKey = request
            } catch is CancellationError { return }
            catch { loaded = nil; loadedKey = request }
        }
    }
}

struct ApplicationAssetThumbnail: View {
    let source: String
    let role: ApplicationIconRolePresentation
    var size: CGFloat = 36
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        ApplicationIconImage(candidates: PublicMediaURL.resolve(source).map { [ApplicationIconCandidate(url: $0, role: role)] } ?? [],
                             size: size, pixelSize: Int((size * displayScale).rounded(.up))) {
            Image(systemName: "photo").foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ApplicationRow: View {
    let application: CloudApplication
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    ApplicationIcon(application: application)
                    description
                    if let label = application.accessLabel { accessLabel(label) }
                }
            } else {
                HStack(spacing: 12) {
                    ApplicationIcon(application: application)
                    description
                    if let label = application.accessLabel { accessLabel(label) }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(application.name).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(application.summary).font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accessLabel(_ label: String) -> some View {
        Text(label).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
