import SwiftUI

struct ContentStateView: View {
    let title: String
    let systemImage: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
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
