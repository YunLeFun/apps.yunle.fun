import SwiftUI

struct NativePublicRoomsView: View {
    let games: [NativeGame]
    let onJoin: (NativeGameRoomIntent) -> Void
    let onCreate: (() -> Void)?
    @StateObject private var store = NativePublicRoomStore()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(games: [NativeGame], onCreate: (() -> Void)? = nil, onJoin: @escaping (NativeGameRoomIntent) -> Void) {
        self.games = games; self.onCreate = onCreate; self.onJoin = onJoin
    }

    var body: some View {
        NavigationStack {
            List {
                if store.isLoading {
                    ProgressView("正在查找公开房间").frame(maxWidth: .infinity, minHeight: 120)
                } else if let error = store.error {
                    ContentStateView(title: "公开房间暂不可用", systemImage: "wifi.exclamationmark", message: error,
                                     actionTitle: "重试", action: refresh)
                        .accessibilityIdentifier("games.public-rooms.error")
                } else if store.rooms.isEmpty {
                    ContentStateView(title: "暂时没有公开房间", systemImage: "person.2", message: "创建房间时开启「公开房间」，邀请大家一起玩。",
                                     actionTitle: onCreate == nil ? "刷新" : "创建房间", action: createOrRefresh)
                        .accessibilityIdentifier("games.public-rooms.empty")
                } else {
                    Section {
                        ForEach(store.rooms) { room in
                            Button {
                                guard let intent = try? room.intent() else { return }
                                onJoin(intent)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(gameName(room)).font(.headline).foregroundStyle(.primary)
                                    Text("\(room.statusTitle) · \(room.memberCount)/\(room.capacity) 人")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    HStack {
                                        Text(room.inviteCode).font(.caption.monospaced()).foregroundStyle(.secondary)
                                        Spacer()
                                        Label(room.actionTitle, systemImage: room.isSpectating ? "eye" : "arrow.right.circle")
                                            .font(.subheadline)
                                    }
                                }
                                .padding(.vertical, 5)
                            }
                            .accessibilityIdentifier("games.public-room.\(room.inviteCode)")
                        }
                    } footer: {
                        Text("进入时确认登录和房间状态；正在对局的房间以观众身份进入。")
                    }
                }
            }
            .navigationTitle("公开房间").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                if onCreate != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: createOrRefresh) { Label("创建房间", systemImage: "plus") }
                            .accessibilityIdentifier("games.public-rooms.create")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: refresh) { Label("刷新", systemImage: "arrow.clockwise") }
                        .disabled(store.isLoading)
                        .accessibilityIdentifier("games.public-rooms.refresh")
                }
            }
            .task { await store.load() }
            .refreshable { await store.load() }
            .onChange(of: scenePhase) { phase in if phase == .active { refresh() } }
        }
    }

    private func refresh() { Task { await store.load() } }
    private func createOrRefresh() {
        if let onCreate { onCreate(); dismiss() }
        else { refresh() }
    }
    private func gameName(_ room: NativePublicRoom) -> String {
        guard let id = room.gameId else { return "一起选游戏" }
        return games.first { $0.gameId == id }?.name
            ?? ["stone-chess": "石子棋", "animal-chess": "斗兽棋", "dark-animal-chess": "暗兽棋", "ganyandyan": "干瞪眼", "snake": "联机贪吃蛇"][id]
            ?? "联机游戏"
    }
}
