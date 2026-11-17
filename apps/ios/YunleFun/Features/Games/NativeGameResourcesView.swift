import SwiftUI

struct NativeGameResourcePreparation: Identifiable {
    let id = UUID()
    let game: NativeGame
    let profileID: UUID
    let boundary: AccountRequestBoundary
}

struct NativeGameResourcesView: View {
    let selection: NativeGameResourcePreparation
    @ObservedObject var cache: NativeGameResourceCache
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false
    @AppStorage("applicationCache.wifiOnly") private var wifiOnly = true
    private var isCurrent: Bool {
        selection.boundary == AccountRequestBoundary(uid: accounts.user?.id, generation: accounts.identityGeneration)
    }
    private var entry: NativeGameResourceCacheEntry? {
        cache.entry(gameID: selection.game.gameId, profileID: selection.profileID)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ApplicationIcon(application: selection.game.iconApplication, size: 52)
                        Text(selection.game.name).font(.headline)
                    }
                    if let entry {
                        if selection.game.resourceVersion == nil || selection.game.resourceVersion == entry.version {
                            Label("资源已准备", systemImage: "checkmark.circle")
                        } else {
                            Label("可准备新版本资源", systemImage: "arrow.triangle.2.circlepath")
                        }
                        LabeledContent("大小", value: ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file))
                        LabeledContent("资源数", value: String(entry.resourceCount))
                        Text(entry.preparedAt, style: .relative).font(.footnote).foregroundStyle(.secondary)
                    } else { Text("按需准备游戏公共资源，减少再次打开时的重复下载。") }
                } footer: { Text("资源由系统缓存并可能被回收。登录、房间与部分游戏功能仍需联网。") }
                Section {
                    if cache.isBusy {
                        if cache.downloadingGameID == selection.game.gameId {
                            ProgressView(value: cache.progress) { Text("正在准备资源") }
                            Button("取消准备") { cache.cancel() }
                        } else { Text("正在准备其他游戏的资源。") }
                    } else if let raw = selection.game.resourceManifestURL, let manifest = URL(string: raw) {
                        Button(entry == nil ? "准备游戏资源" : "重新准备最新资源") {
                            guard isCurrent else { return }
                            cache.download(manifestURL: manifest, gameID: selection.game.gameId,
                                           profileID: selection.profileID, wifiOnly: wifiOnly)
                        }
                        .disabled(!isCurrent)
                        .accessibilityIdentifier("games.resources.prepare")
                    }
                    Toggle("仅在 Wi-Fi 下准备", isOn: $wifiOnly)
                        .onChange(of: wifiOnly) { _ in cache.cancel() }
                } footer: { Text("单款最多准备 25 MB，已登记资源合计最多 200 MB。") }
                if let error = cache.error {
                    Section { Text(error).foregroundStyle(.secondary).accessibilityIdentifier("games.resources.error") }
                }
                if cache.hasResources(profileID: selection.profileID) {
                    Section {
                        Button("清理游戏资源缓存", role: .destructive) { confirmClear = true }
                            .disabled(!isCurrent || cache.isClearing)
                    } footer: { Text("同一游戏空间的资源一起清理，游戏存档和登录会保留。") }
                }
            }
            .navigationTitle("游戏资源").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .confirmationDialog("清理这个游戏空间的资源缓存？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清理资源缓存", role: .destructive) {
                    guard isCurrent else { return }
                    Task { await cache.clear(profileID: selection.profileID) }
                }
            } message: { Text("共享此空间的其他游戏资源也会清理。账号、登录和游戏存档都会保留。") }
        }
    }
}
