import SwiftUI

struct RoomInviteCard: View {
    let gameName: String
    let inviterName: String
    let hasReplied: Bool
    let replyLater: (() async throws -> Void)?
    let join: () -> Void

    @State private var isReplying = false
    @State private var replied = false
    @State private var replyError: String?

    init(gameName: String, inviterName: String, hasReplied: Bool = false,
         replyLater: (() async throws -> Void)? = nil, join: @escaping () -> Void) {
        self.gameName = gameName
        self.inviterName = inviterName
        self.hasReplied = hasReplied
        self.replyLater = replyLater
        self.join = join
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: gameName).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text("\(inviterName) 邀请你一起玩").foregroundStyle(.secondary)
            Button(action: join) {
                Text("加入房间").frame(minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("games.invitation.join")
            if replyLater != nil {
                if hasReplied || replied {
                    Text("⏳ 已回复「稍后再玩」").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Button {
                        isReplying = true
                    } label: {
                        Text(isReplying ? "正在回复…" : "⏳ 稍后再玩")
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(isReplying ? "正在回复" : "稍后再玩")
                    .accessibilityIdentifier("games.invitation.reply-later")
                    .disabled(isReplying)
                }
            }
            if let replyError {
                Text(replyError).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: isReplying) {
            guard isReplying, let replyLater else { return }
            defer { isReplying = false }
            replyError = nil
            do {
                try await replyLater()
                if !Task.isCancelled { replied = true }
            } catch {
                if !Task.isCancelled { replyError = roomInviteErrorMessage(error) }
            }
        }
    }
}

@MainActor
struct RoomInviteInbox: View {
    @ObservedObject var accounts: AccountStore
    @EnvironmentObject private var games: NativeGameCatalogStore
    @State private var repliesEnabled = false
    @State private var joinedProjectID: String?
    @State private var openWebBuild = false
    let service: RoomInviteService
    let joinRoom: (NativeGameRoomIntent) -> Void

    var body: some View {
        RoomInviteList(emptyTitle: "还没有邀请", emptyIcon: "tray", fetch: fetch) { (message: RoomInviteMessage) in
            if message.isLaterReply {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: gameName(for: message.roomInviteGameId)).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text("⏳ \(message.actor.nickname) 回复了「稍后再玩」").foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if let invite = message.roomInvite, let room = invite.intent {
                RoomInviteCard(gameName: gameName(for: invite.gameId), inviterName: message.actor.nickname,
                               hasReplied: message.hasRepliedLater,
                               replyLater: repliesEnabled ? { try await replyLater(to: message.id) } : nil) {
                    joinRoom(room)
                }
                .padding(.vertical, 8)
            } else if let invite = message.webBuild {
                WebBuildFriendInviteCard(invite: invite, inviterName: message.actor.nickname) {
                    let access = AccountRequestAccess<PublishingError>(accounts: accounts)
                    let receipt = try await access.perform(boundary: access.boundary) { identity in
                        try await WebBuildService().room(.acceptInvite(message.id, projectID: invite.projectId),
                                                        projectID: nil, identity: identity)
                    }
                    guard let project = receipt.project else { throw PublishingError.invalidResponse }
                    joinedProjectID = project.id
                    openWebBuild = true
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("消息")
        .navigationDestination(isPresented: $openWebBuild) {
            if let joinedProjectID { WebBuildEditorView(projectID: joinedProjectID) }
        }
    }

    private func gameName(for id: String?) -> String {
        id.flatMap { id in games.catalog?.games.first { $0.gameId == id }?.name } ?? "联机房间"
    }

    private func fetch(skip: Int) async throws -> RoomInvitePage<RoomInviteMessage> {
        let access = AccountRequestAccess<RoomInviteError>(accounts: accounts)
        let page = try await access.perform(boundary: access.boundary) { identity in
            try await service.messages(skip: skip, identity: identity)
        }
        if !Task.isCancelled { repliesEnabled = page.repliesEnabled == true }
        return page
    }

    private func replyLater(to id: String) async throws {
        let access = AccountRequestAccess<RoomInviteError>(accounts: accounts)
        try await access.perform(boundary: access.boundary) { identity in
            try await service.replyLater(to: id, identity: identity)
        }
    }
}

@MainActor
struct RoomInvitePicker: View {
    @ObservedObject var accounts: AccountStore
    let service: RoomInviteService
    let room: NativeGameRoomIntent
    let currentRoom: () -> NativeGameRoomIntent?

    var body: some View {
        MutualFriendInvitePicker(accounts: accounts, service: service) { friend, identity in
            guard currentRoom() == room else { throw RoomInviteError.roomUnavailable }
            try await service.send(room: room, to: friend, identity: identity)
        }
    }
}

@MainActor
struct MutualFriendInvitePicker: View {
    @ObservedObject var accounts: AccountStore
    let service: RoomInviteService
    var sendIdentifier = "games.invite.send"
    let send: (RoomInviteFriend, AuthorizedAccount) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sending: RoomInviteFriend?
    @State private var sent: Set<String> = []
    @State private var sendError: String?

    var body: some View {
        NavigationStack {
            RoomInviteList(emptyTitle: "还没有互关好友", emptyIcon: "person.2", fetch: fetch,
                           actionError: sendError) { (friend: RoomInviteFriend) in
                HStack {
                    VStack(alignment: .leading) {
                        Text(verbatim: friend.nickname)
                        if let login = friend.login { Text("@\(login)").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if sent.contains(friend.id) {
                        Text("已发送").foregroundStyle(.secondary)
                    } else if sending?.id == friend.id {
                        ProgressView().accessibilityLabel("正在发送")
                    } else {
                        Button("发送") { sending = friend }.buttonStyle(.bordered)
                            .disabled(sending != nil)
                            .accessibilityLabel("发送邀请给\(friend.nickname)")
                            .accessibilityIdentifier(sendIdentifier)
                    }
                }
            }
            .navigationTitle("邀请好友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        }
        .task(id: sending?.id) {
            guard let friend = sending else { return }
            defer { sending = nil }
            sendError = nil
            let access = AccountRequestAccess<RoomInviteError>(accounts: accounts)
            do {
                try await access.perform(boundary: access.boundary) { identity in
                    try await send(friend, identity)
                }
                sent.insert(friend.id)
            } catch {
                if !Task.isCancelled {
                    sendError = (error as? PublishingError)?.message ?? roomInviteErrorMessage(error)
                }
            }
        }
    }

    private func fetch(skip: Int) async throws -> RoomInvitePage<RoomInviteFriend> {
        let access = AccountRequestAccess<RoomInviteError>(accounts: accounts)
        return try await access.perform(boundary: access.boundary) { identity in
            try await service.friends(skip: skip, identity: identity)
        }
    }
}

@MainActor
private struct RoomInviteList<Item: Identifiable & Decodable, Row: View>: View {
    let emptyTitle: String
    let emptyIcon: String
    let fetch: (Int) async throws -> RoomInvitePage<Item>
    var actionError: String? = nil
    @ViewBuilder let row: (Item) -> Row

    @State private var items: [Item] = []
    @State private var nextSkip: Int? = 0
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        List {
            if let actionError { Text(actionError).foregroundStyle(.red) }
            ForEach(items, content: row)
            if isLoading {
                ProgressView("正在载入…")
            } else if let loadError {
                Text(loadError).foregroundStyle(.secondary)
                Button("重试") { Task { await load() } }
            } else if let nextSkip, nextSkip > 0 {
                Button("加载更多") { Task { await load() } }
            } else if items.isEmpty, nextSkip == nil {
                Label(emptyTitle, systemImage: emptyIcon).foregroundStyle(.secondary)
            }
        }
        .task { await load() }
        .refreshable { await load(reset: true) }
    }

    private func load(reset: Bool = false) async {
        guard !isLoading, let skip = reset ? 0 : nextSkip else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let page = try await fetch(skip)
            try Task.checkCancellation()
            if skip == 0 { items = page.items }
            else {
                let existing = Set(items.map(\.id))
                items.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            }
            nextSkip = page.nextSkip
        } catch {
            if !Task.isCancelled {
                if reset { nextSkip = 0 }
                loadError = roomInviteErrorMessage(error)
            }
        }
    }
}

private func roomInviteErrorMessage(_ error: Error) -> String {
    (error as? RoomInviteError)?.errorDescription ?? AccountError.message(for: error)
}
