import SwiftUI

struct ApplicationIcon: View {
    let application: CloudApplication
    var size: CGFloat = 52
    var pipeline: ApplicationImagePipeline = .shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            CatalogApplicationIconImage(application: application,
                                 pixelSize: Int((size * displayScale).rounded(.up)), pipeline: pipeline) { fallback }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Group {
            if application.isUnavailable == true, application.emoji?.nilIfEmpty == nil {
                ZStack {
                    Color(uiColor: .quaternarySystemFill)
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .strokeBorder(.secondary, style: StrokeStyle(lineWidth: max(1, size / 64), dash: [size * 0.065, size * 0.05]))
                    Image(systemName: "app")
                        .font(.system(size: size * 0.4, weight: .light))
                        .foregroundStyle(.secondary)
                }
            } else {
                ZStack {
                    Color(uiColor: .tertiarySystemFill)
                    ApplicationPlaceholderImage(text: application.emoji?.nilIfEmpty ?? String(application.name.prefix(1)),
                                                size: size, scale: displayScale, colorScheme: colorScheme)
                }
                .modifier(ApplicationIconAvailabilityStyle(isUnavailable: application.isUnavailable == true))
            }
        }
    }
}

private struct ApplicationPlaceholderImage: View {
    let text: String
    let size: CGFloat
    let scale: CGFloat
    let colorScheme: ColorScheme

    var body: some View {
        Group {
            if let image = ApplicationPlaceholderImages.image(text: text, size: size, scale: scale, colorScheme: colorScheme) {
                Image(uiImage: image).renderingMode(.original).resizable().scaledToFit()
            } else { Image(systemName: "app") }
        }
    }
}

@MainActor
private enum ApplicationPlaceholderImages {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 128
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    static func image(text: String, size: CGFloat, scale: CGFloat, colorScheme: ColorScheme) -> UIImage? {
        let key = "\(text)|\(size)|\(scale)|\(colorScheme)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let renderer = ImageRenderer(content: Text(text)
            .font(.system(size: size * 0.48, weight: .medium))
            .foregroundStyle(Color.primary)
            .minimumScaleFactor(0.5)
            .frame(width: size, height: size)
            .environment(\.colorScheme, colorScheme))
        renderer.scale = scale
        guard let image = renderer.uiImage else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}

struct ApplicationAssetThumbnail: View {
    let source: String
    let role: ApplicationIconRolePresentation
    var size: CGFloat = 36
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        ApplicationIconImage(candidates: PublicMediaURL.resolve(source).map { [ApplicationIconCandidate(url: $0, role: role)] } ?? [],
                             pixelSize: Int((size * displayScale).rounded(.up))) {
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
            Text(application.name).font(.headline).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
            // Two lines keep long catalogs scannable; the detail page and
            // VoiceOver still get the full summary. Accessibility sizes stay unclamped.
            Text(application.summary).font(.subheadline).foregroundStyle(Color.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func accessLabel(_ label: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text(label).font(.caption).foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // A compact capsule that never wraps character by character beside the summary.
            Text(label).font(.caption.weight(.medium)).foregroundStyle(Color.primary)
                .lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                .fixedSize()
        }
    }
}
