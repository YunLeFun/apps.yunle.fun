import SwiftUI

struct GamesView: View {
    @ObservedObject var store: NativeGameCatalogStore
    @ObservedObject var history: NativeGameHistoryStore
    let open: (NativeGame, NativeGameMode) -> Void
    let resume: (String) -> Void
    let runningGameIDs: Set<String>
    let onRoom: (NativeGameRoomIntent) -> Void
    let continuationRoom: NativeGameRoomIntent?
    var fallback: ((NativeGame) -> Void)? = nil
    var prepareResources: ((NativeGame) -> Void)? = nil
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var query = ""
    @State private var filter = GameFilter.all
    @State private var joinSheet: JoinSheet?
    @State private var pendingRoom: NativeGameRoomIntent?
    @State private var pendingRoomIdentity: UUID?

    private struct JoinSheet: Identifiable { let id = UUID(); let identity: UUID }
    private enum GameFilter: String, CaseIterable, Identifiable {
        case all = "全部", solo = "单人", local = "同屏", online = "联机"
        var id: Self { self }
        func matches(_ game: NativeGame) -> Bool {
            switch self {
            case .all: return true
            case .solo: return game.launchModes.contains { ["computer", "tutorial", "pve"].contains($0.id) }
            case .local: return game.launchModes.contains { $0.id == "local" }
            case .online: return game.launchModes.contains { $0.id == "online" }
            }
        }
    }

    private var isBrowsing: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filter == .all }
    private var visibleGames: [NativeGame] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.games.filter { game in
            filter.matches(game) && (term.isEmpty || ([game.name, game.description] + game.launchModes.map(\.title))
                .contains { $0.localizedStandardContains(term) })
        }
    }
    private var runningGames: [NativeGame] { store.games.filter { runningGameIDs.contains($0.gameId) } }
    private var recentGames: [(NativeGameHistoryEntry, NativeGame, NativeGameMode)] {
        history.entries.prefix(6).compactMap { entry in
            guard let game = store.game(id: entry.gameID), let mode = game.mode(id: entry.modeID) else { return nil }
            return (entry, game, mode)
        }
    }

    var body: some View {
        List {
            catalogNotice
            if isBrowsing {
                runningSection
                roomSection
                recentSection
            }
            gamesSection
        }
        .navigationTitle("寻乐")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(dynamicTypeSize.isAccessibilitySize ? "搜索游戏" : "搜索游戏或玩法"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { joinSheet = JoinSheet(identity: accounts.identityGeneration) } label: { Label("加入房间", systemImage: "person.2.badge.plus") }
                    .accessibilityIdentifier("games.join-room")
                    .disabled(accounts.isRestoring || accounts.isInitialRestorePending)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("玩法", selection: $filter) {
                        ForEach(GameFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Label("玩法", systemImage: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityValue(filter.rawValue)
                .accessibilityIdentifier("games.filter")
            }
        }
        .sheet(item: $joinSheet, onDismiss: continueRequestedRoom) { sheet in
            GameRoomJoinView { intent in
                guard sheet.identity == accounts.identityGeneration else { return }
                pendingRoom = intent
                pendingRoomIdentity = sheet.identity
            }
        }
        .task(id: accounts.identityGeneration) {
            history.activate(accountID: accounts.user?.id)
            await store.load()
        }
        .onChange(of: accounts.identityGeneration) { _ in
            pendingRoom = nil
            pendingRoomIdentity = nil
            joinSheet = nil
        }
        .refreshable { await store.load(force: true) }
    }

    @ViewBuilder private var catalogNotice: some View {
        if let error = store.error, !store.games.isEmpty {
            Section {
                HStack {
                    Label("游戏列表暂未更新", systemImage: "wifi.exclamationmark").font(.subheadline)
                    Spacer()
                    Button("重试") { Task { await store.load(force: true) } }
                }
                .accessibilityIdentifier("games.catalog-notice")
                .accessibilityHint(error)
            } footer: { Text("可以继续浏览已收录的游戏，进入时会确认玩法是否可用。") }
        }
        if let notice = store.storageNotice { Section { Text(notice).font(.footnote).foregroundStyle(.secondary) } }
    }

    @ViewBuilder private var runningSection: some View {
        if !runningGames.isEmpty {
            Section("继续游戏") {
                ForEach(runningGames) { game in
                    Button { resume(game.gameId) } label: {
                        gameSummary(game, subtitle: "恢复正在运行的游戏", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(accounts.isRestoring)
                    .accessibilityIdentifier("games.resume.\(game.gameId)")
                }
            }
        }
    }

    @ViewBuilder private var roomSection: some View {
        if let room = continuationRoom {
            Section {
                Button { onRoom(room) } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("返回上次房间")
                            Text("\(room.inviteCode) · \(room.role == .spectator ? "观战" : "加入对局")")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "arrow.uturn.backward.circle") }
                }
                .accessibilityIdentifier("games.continue-room")
                .disabled(accounts.isRestoring)
                ShareLink(item: room.url) { Label("分享房间邀请", systemImage: "square.and.arrow.up") }
                    .accessibilityIdentifier("games.share-room")
            } footer: { Text("进入时会重新确认房间和席位是否仍可用。") }
        }
    }

    @ViewBuilder private var recentSection: some View {
        if !recentGames.isEmpty {
            Section("最近玩过") {
                ForEach(recentGames, id: \.0.id) { _, game, mode in
                    Button { open(game, mode) } label: { gameSummary(game, subtitle: mode.title, systemImage: "clock") }
                        .buttonStyle(.plain)
                        .disabled(accounts.isRestoring || !game.isPlayable || !mode.available)
                        .accessibilityIdentifier("games.recent.\(game.gameId)")
                }
            }
        }
    }

    @ViewBuilder private var gamesSection: some View {
        if store.games.isEmpty && store.isLoading {
            Section { ProgressView("正在寻找好玩的游戏").frame(maxWidth: .infinity, minHeight: 160) }
        } else if store.games.isEmpty {
            Section {
                ContentStateView(title: "游戏列表暂不可用", systemImage: "gamecontroller",
                                 message: store.error ?? "稍后刷新，看看新收录的游戏。", actionTitle: "刷新",
                                 action: { Task { await store.load(force: true) } })
            }
        } else if visibleGames.isEmpty {
            Section {
                ContentStateView(title: "没有找到相关游戏", systemImage: "magnifyingglass", message: "试试其他关键词或玩法。",
                                 actionTitle: "显示全部", action: { query = ""; filter = .all })
            }
        } else {
            Section(isBrowsing ? "精选游戏" : "游戏 · \(visibleGames.count)") {
                ForEach(visibleGames) { game in gameCard(game) }
            }
        }
    }

    private func gameCard(_ game: NativeGame) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ApplicationIcon(application: game.iconApplication, size: 56)
                VStack(alignment: .leading, spacing: 5) {
                    Text(game.name).font(.headline)
                    if let players = game.players { Label(players.label, systemImage: "person.2").font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(game.description).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 180 : 112), alignment: .leading)], alignment: .leading, spacing: 10) {
                ForEach(game.launchModes) { mode in
                    Button { open(game, mode) } label: {
                        Text(mode.title).font(.subheadline).frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.bordered)
                    .disabled(accounts.isRestoring || !game.isPlayable || !mode.available)
                    .accessibilityLabel("\(game.name)，\(mode.title)")
                    .accessibilityHint(mode.available ? (mode.requiresLogin ? "联网玩法，进入时确认登录。" : "直接进入这个玩法。") : "当前客户端暂未提供这个玩法，可在 Play 中查看。")
                    .accessibilityIdentifier("games.launch.\(game.gameId).\(mode.id)")
                }
            }
            if game.launchModes.allSatisfy({ !$0.available }) {
                Text("当前客户端暂未提供这些玩法，可在 Play 中查看游戏。")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if game.availableModes.contains(where: \.requiresNetwork) {
                Text("联机玩法需要联网，进入时确认房间与登录状态。")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if game.fallbackURL != nil, let fallback {
                Button { fallback(game) } label: { Label("在 Play 查看玩法", systemImage: "arrow.up.forward.app") }
                    .accessibilityIdentifier("games.fallback.\(game.gameId)")
            }
            if game.resourceManifestURL != nil, let prepareResources {
                Button { prepareResources(game) } label: { Label("游戏资源", systemImage: "arrow.down.circle") }
                    .accessibilityIdentifier("games.resources.\(game.gameId)")
            }
        }
        .padding(.vertical, 10)
        .accessibilityIdentifier("games.game.\(game.gameId)")
    }

    private func gameSummary(_ game: NativeGame, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            ApplicationIcon(application: game.iconApplication, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(game.name).foregroundStyle(Color.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: systemImage).foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private func continueRequestedRoom() {
        let intent = pendingRoom
        let identity = pendingRoomIdentity
        pendingRoom = nil
        pendingRoomIdentity = nil
        guard let intent, identity == accounts.identityGeneration else { return }
        onRoom(intent)
    }
}

private struct GameRoomJoinView: View {
    let onJoin: (NativeGameRoomIntent) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var role = NativeGameRoomIntent.Role.player
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("六位房间号或邀请链接", text: $input)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .focused($focused).submitLabel(.go).onSubmit(join)
                        .accessibilityIdentifier("games.room-input")
                    Picker("进入方式", selection: $role) {
                        Text("加入对局").tag(NativeGameRoomIntent.Role.player)
                        Text("观战").tag(NativeGameRoomIntent.Role.spectator)
                    }
                } footer: { Text("邀请链接会保留其中指定的进入方式。进入后会确认房间是否可用，联机需要登录。") }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("games.room-error") } }
                Section {
                    Button("继续", action: join).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("games.room-submit")
                }
            }
            .navigationTitle("加入房间").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }

    private func join() {
        do {
            let intent = try NativeGameRoomIntent(input: input, role: role)
            focused = false
            onJoin(intent)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
