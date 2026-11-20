import SwiftUI

struct AssistantRoomCardView: View {
    let code: String
    @EnvironmentObject private var feed: AssistantRoomFeed
    @EnvironmentObject private var games: NativeGameCatalogStore
    @Environment(\.requestGameRoom) private var requestRoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(room?.gameName(in: games.games) ?? "公开联机房间", systemImage: "person.2")
                .font(.headline)
            Text("房间号 \(code)").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            switch feed.state {
            case .loading:
                status("正在核对房间状态")
            case .unavailable:
                status("暂时无法更新房间，正在重试")
            case .current:
                if let room { availableRoom(room) }
                else { status("房间暂不在公开列表") }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("assistant.room-card.\(code)")
    }

    private var room: NativePublicRoom? {
        guard case .current(let rooms) = feed.state else { return nil }
        return rooms.first { $0.inviteCode == code }
    }

    private func status(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.subheadline).foregroundStyle(.secondary)
    }

    private func availableRoom(_ room: NativePublicRoom) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(room.statusTitle).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(0..<room.capacity, id: \.self) { index in
                    Capsule()
                        .fill(index < room.memberCount ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                        .frame(maxWidth: 24).frame(height: 8)
                }
            }
            .accessibilityHidden(true)
            .animation(reduceMotion ? nil : Motion.fade, value: room.memberCount)
            Text("已占 \(room.memberCount)/\(room.capacity) 席")
                .font(.subheadline.monospacedDigit())
                .accessibilityLabel("已占 \(room.memberCount) 席，共 \(room.capacity) 席")
                .accessibilityIdentifier("assistant.room-card.seats.\(code)")
            Button {
                guard let current = self.room, current.isSpectating == room.isSpectating,
                      let intent = try? current.intent() else { return }
                requestRoom?(intent)
            } label: {
                Label(room.actionTitle, systemImage: room.isSpectating ? "eye" : "arrow.right.circle")
                    .frame(minHeight: 36)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .disabled(requestRoom == nil)
            .accessibilityIdentifier("assistant.room-card.action.\(code)")
        }
    }
}

private struct GameRoomRequestKey: EnvironmentKey {
    static let defaultValue: ((NativeGameRoomIntent) -> Void)? = nil
}

extension EnvironmentValues {
    var requestGameRoom: ((NativeGameRoomIntent) -> Void)? {
        get { self[GameRoomRequestKey.self] }
        set { self[GameRoomRequestKey.self] = newValue }
    }
}
