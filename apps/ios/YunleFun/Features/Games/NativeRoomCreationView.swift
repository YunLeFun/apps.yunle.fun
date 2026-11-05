import SwiftUI

struct NativeRoomCreationView: View {
    @ObservedObject private var accounts: AccountStore
    @StateObject private var model: NativeRoomCreationStore
    @State private var draft: NativeRoomCreationDraft
    @State private var request: Task<Void, Never>?
    let games: [NativeGame]
    let initialGameID: String?
    let onCreated: (NativeGameRoomIntent) -> Void
    @Environment(\.dismiss) private var dismiss

    init(accounts: AccountStore, games: [NativeGame], gameID: String?, service: NativeRoomCreating = NativeRoomCreationService(),
         onCreated: @escaping (NativeGameRoomIntent) -> Void) {
        self.accounts = accounts; self.games = games; self.onCreated = onCreated
        let model = NativeRoomCreationStore(accounts: accounts, service: service)
        _model = StateObject(wrappedValue: model)
        let available = games.contains { $0.gameId == gameID && $0.mode(id: "online")?.available == true }
        initialGameID = available && NativeRoomCreationDraft.rulesets[gameID ?? ""] != nil ? gameID : nil
        _draft = State(initialValue: model.operation?.draft ?? .init(gameID: initialGameID))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let code = model.operation?.inviteCode {
                    Section {
                        Label("上次创建的房间", systemImage: "checkmark.circle.fill")
                        Text(code).font(.title2.monospaced()).textSelection(.enabled)
                        LabeledContent("游戏", value: draft.gameID.flatMap { id in games.first { $0.gameId == id }?.name } ?? "先开房，再选游戏")
                        Text(draft.isPublic ? "公开房间" : "私密房间").foregroundStyle(.secondary)
                        Button("进入已创建的房间") { submit() }.accessibilityIdentifier("games.create.enter")
                        Button("创建另一个房间") { model.startAnother(); draft = .init(gameID: initialGameID) }
                    } footer: { Text("保留上次创建结果，方便返回，也避免重试时重复创建。") }
                } else {
                    Section {
                        Picker("游戏", selection: $draft.gameID) {
                            Text("先开房，再选游戏").tag(String?.none)
                            ForEach(games.filter { $0.isPlayable && $0.mode(id: "online")?.available == true && NativeRoomCreationDraft.rulesets[$0.gameId] != nil }) { game in
                                Text(game.name).tag(Optional(game.gameId))
                            }
                        }.accessibilityIdentifier("games.create.game")
                        LabeledContent("房间容量", value: "4 人")
                    }.disabled(model.operation != nil || model.isCreating)
                    Section {
                        Toggle("公开房间", isOn: $draft.isPublic).accessibilityIdentifier("games.create.public")
                    } footer: {
                        Text(draft.isPublic ? "房间会显示在公开房间列表，其他玩家可以直接加入。" : "仅凭房间号或邀请链接加入，不显示在公开房间列表。")
                    }.disabled(model.operation != nil || model.isCreating)
                    Section {
                        Text("使用当前云乐坊账号创建房间。")
                        Button { submit(consent: model.needsConsent) } label: {
                            if model.isCreating { HStack { ProgressView(); Text("正在创建房间…") } }
                            else { Text(model.needsConsent ? "允许使用当前账号并创建" : model.operation == nil ? "创建并进入房间" : "重试创建") }
                        }.disabled(model.isCreating).accessibilityIdentifier("games.create.submit")
                    }
                    if model.operation != nil { Section { Text("为避免重复创房，重试将使用原来的游戏和公开设置。").font(.footnote).foregroundStyle(.secondary) } }
                }
                if let error = model.error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("games.create.error") } }
            }
            .navigationTitle("创建房间").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { request?.cancel(); dismiss() } } }
            .interactiveDismissDisabled(model.isCreating)
            .onDisappear { request?.cancel() }
        }
    }

    private func submit(consent: Bool = false) {
        guard request == nil else { return }
        request = Task {
            defer { request = nil }
            guard let room = await model.create(draft, consent: consent), !Task.isCancelled else { return }
            onCreated(room); dismiss()
        }
    }
}
