import SwiftUI

struct NativeConversationCardView: View {
    let reference: ConversationCardReference
    let fallback: String
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var chat: AssistantStore

    var body: some View {
        ConversationCardContent(reference: reference, fallback: fallback, accounts: accounts, service: chat.cardService)
            .id(accounts.identityGeneration)
    }
}

struct LinkedConversationCardView: View {
    let link: ConversationCardLink
    @EnvironmentObject private var accounts: AccountStore

    var body: some View {
        ScrollView {
            if accounts.user?.isUsable == true {
                NativeConversationCardView(reference: link.reference, fallback: "共享卡片")
                    .frame(maxWidth: 440)
                    .padding(16)
                    .frame(maxWidth: .infinity)
            } else {
                ContentStateView(title: "请登录后继续", systemImage: "person.crop.circle",
                                 message: "登录云乐坊后可以打开共享卡片。")
                    .padding(16)
            }
        }
        .navigationTitle("共享卡片")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ConversationCardContent: View {
    let reference: ConversationCardReference
    let fallback: String
    let accounts: AccountStore
    let service: NativeConversationCardServing
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var snapshot: NativeConversationCardSnapshot?
    @State private var readError: String?
    @State private var actionError: String?
    @State private var pending: NativeConversationCardAction?
    @State private var watchID: UUID?
    @State private var connected = false

    private var canInteract: Bool { connected && pending == nil && scenePhase == .active && snapshot?.finished == false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot {
                ForEach(snapshot.template.components.indices, id: \.self) { index in
                    component(snapshot.template.components[index], in: snapshot)
                }
                ShareLink(item: ConversationCardLink(reference: reference).url) {
                    Label("分享卡片", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("assistant.card.share")
            } else {
                Text(verbatim: fallback).font(.headline)
            }
            if let message = readError ?? actionError {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            } else if pending != nil {
                Text("正在确认操作…").font(.footnote).foregroundStyle(.secondary)
            } else if snapshot == nil {
                Text("正在同步卡片…").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task(id: scenePhase) {
            if scenePhase == .active { await watch() }
        }
        .task(id: pending) {
            if let pending { await send(pending) }
        }
    }

    @ViewBuilder private func component(_ component: NativeConversationCardSnapshot.Component,
                                        in snapshot: NativeConversationCardSnapshot) -> some View {
        switch component.kind {
        case .title:
            if let text = snapshot.text(component.field) {
                Text(verbatim: text).font(.headline).accessibilityAddTraits(.isHeader)
            }
        case .text:
            if let text = snapshot.text(component.field), !text.isEmpty {
                Text(verbatim: text).font(.subheadline)
            }
        case .seats:
            if let filled = snapshot.number(component.filled), let total = snapshot.number(component.total) {
                ConversationCardSeats(capacity: total, occupied: Double(filled))
                    .animation(reduceMotion ? nil : Motion.fade, value: filled)
                    .accessibilityLabel("已占用 \(filled) 席，共 \(total) 席")
            }
        case .button:
            if let name = component.action, let action = snapshot.actions[name] {
                Button { submit(name, revision: snapshot.revision) } label: { Text(verbatim: action.label) }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    .disabled(!canInteract || !action.enabled)
                    .accessibilityIdentifier("assistant.card." + name)
            }
        case .gomoku:
            if let name = component.action, let board = snapshot.board(component.field) {
                ConversationBoardCanvas(snapshot: board, interactive: canInteract && snapshot.actions[name]?.enabled == true && board.canPlace,
                                        pendingPosition: pendingPosition(for: name, revision: snapshot.revision)) { point in
                    submit(name, revision: snapshot.revision, input: ["row": point.row, "column": point.column])
                }
            }
        }
    }

    private func pendingPosition(for action: String, revision: Int) -> ConversationBoardPosition? {
        guard let pending, pending.action == action, pending.expectedRevision == revision,
              let row = pending.input?["row"], let column = pending.input?["column"] else { return nil }
        return ConversationBoardPosition(row: row, column: column)
    }

    private func submit(_ name: String, revision: Int, input: [String: Int]? = nil) {
        guard canInteract, snapshot?.revision == revision, snapshot?.actions[name]?.enabled == true else { return }
        actionError = nil
        pending = NativeConversationCardAction(action: name, actionId: UUID().uuidString.lowercased(),
                                               expectedRevision: revision, input: input)
    }

    @MainActor private func watch() async {
        guard snapshot?.finished != true else { return }
        let access = AccountRequestAccess<NativeConversationCardError>(accounts: accounts)
        let boundary = access.boundary
        let id = UUID()
        watchID = id
        connected = false
        defer { if watchID == id { connected = false } }
        var delay: UInt64 = 1
        while !Task.isCancelled && access.isCurrent(boundary) && watchID == id {
            do {
                let events = try await access.perform(boundary: boundary) { try await service.events(reference, identity: $0) }
                var received = false
                for try await value in events {
                    guard !Task.isCancelled, access.isCurrent(boundary), watchID == id else { return }
                    received = true
                    apply(value)
                    connected = true
                    readError = nil
                    if snapshot?.finished == true { return }
                }
                guard received else { throw NativeConversationCardError.unavailable }
                delay = 1
            } catch {
                guard !Task.isCancelled, access.isCurrent(boundary), watchID == id else { return }
                connected = false
                let error = error as? NativeConversationCardError ?? .unavailable
                readError = error.errorDescription
                if error == .unsupported || error == .forbidden || error == .missing || error == .unauthorized {
                    snapshot = nil
                    return
                }
                delay = min(delay * 2, 15)
            }
            do { try await Task.sleep(nanoseconds: delay * 1_000_000_000) }
            catch { return }
        }
    }

    @MainActor private func send(_ action: NativeConversationCardAction) async {
        let access = AccountRequestAccess<NativeConversationCardError>(accounts: accounts)
        let boundary = access.boundary
        defer { if pending == action { pending = nil } }
        do {
            let value = try await access.perform(boundary: boundary) { try await service.act(action, on: reference, identity: $0) }
            apply(value)
        } catch {
            guard !Task.isCancelled, access.isCurrent(boundary) else { return }
            if let value = try? await access.perform(boundary: boundary, action: { try await service.load(reference, identity: $0) }) {
                apply(value)
            }
            guard !Task.isCancelled, access.isCurrent(boundary) else { return }
            actionError = (error as? NativeConversationCardError ?? .unavailable).errorDescription
        }
    }

    private func apply(_ value: NativeConversationCardSnapshot) {
        guard value.revision >= (snapshot?.revision ?? 0), value != snapshot else { return }
        snapshot = value
    }
}

private struct ConversationCardSeats: View, Animatable {
    let capacity: Int
    var occupied: Double
    var animatableData: Double {
        get { occupied }
        set { occupied = newValue }
    }

    var body: some View {
        let columns = min(capacity, 8)
        Canvas { context, size in
            let width = min(24, max(0, (size.width - CGFloat(columns - 1) * 6) / CGFloat(columns)))
            for index in 0..<capacity {
                let rect = CGRect(x: CGFloat(index % columns) * (width + 6), y: CGFloat(index / columns) * 14,
                                  width: width, height: 8)
                let path = Path(roundedRect: rect, cornerRadius: 4)
                context.fill(path, with: .color(Color(uiColor: .tertiarySystemFill)))
                let fill = min(1, max(0, occupied - Double(index)))
                context.fill(path, with: .color(Color.accentColor.opacity(fill)))
            }
        }
        .frame(height: capacity > 8 ? 22 : 8)
    }
}
