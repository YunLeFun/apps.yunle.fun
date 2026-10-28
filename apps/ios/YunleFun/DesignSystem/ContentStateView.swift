import SwiftUI

/// A quiet system indicator shared by page overlays and toolbar items.
/// Fast requests finish before it appears; cancellation never leaves it visible.
struct LoadingIndicator: View {
    var isLoading = true
    var label = "正在载入"
    @State private var isVisible = false

    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .opacity(isLoading && isVisible ? 1 : 0)
            .accessibilityLabel(Text(label))
            .accessibilityHidden(!isLoading || !isVisible)
            .allowsHitTesting(false)
            .task(id: isLoading) {
                isVisible = false
                guard isLoading else { return }
                do { try await Task.sleep(nanoseconds: 200_000_000) }
                catch { return }
                guard !Task.isCancelled else { return }
                isVisible = true
            }
    }
}

extension View {
    /// Attach to the page container so loading never inserts a row or shifts content.
    /// Pull-to-refresh supplies its own indicator; callers suppress this one while refreshing.
    func loadingOverlay(_ isLoading: Bool, label: String = "正在载入", alignment: Alignment = .top) -> some View {
        overlay(alignment: alignment) {
            LoadingIndicator(isLoading: isLoading, label: label)
                .padding(16)
        }
    }
}

struct ContentStateView: View {
    let title: String
    let systemImage: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        if #available(iOS 17, *) {
            // The system view keeps spacing, type and symbol rendering in step
            // with each OS release.
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
            } actions: {
                if let actionTitle, let action {
                    Button(actionTitle, action: action).buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            legacy
        }
    }

    private var legacy: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.title3.bold())
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

struct CatalogStatusView: View {
    @EnvironmentObject private var catalog: CatalogStore

    var body: some View {
        if catalog.isCached {
            Label(catalog.error == nil ? "正在更新已保存的目录" : "暂时无法更新，显示已保存的目录", systemImage: "clock.arrow.circlepath")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
