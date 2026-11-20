import SwiftUI

struct WebBuildRoomView: View {
    @ObservedObject var store: WebBuildStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var message = ""
    @State private var memberToRemove: WebBuildRoom.Member?
    @State private var confirmLeave = false

    var body: some View {
        Form {
            if let project = store.project {
                if let room = project.room {
                    members(room, canManage: project.canManagePublication)
                    chat(room)
                }
                if project.canManagePublication { invitations(project.room) }
                else {
                    Button("退出协作", role: .destructive) { confirmLeave = true }
                        .disabled(store.isWorking)
                }
            }
            if store.isWorking { ProgressView("正在同步") }
            if let error = store.error {
                Text(verbatim: error).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("项目协作")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: activeRoomID) {
            if let id = activeRoomID { await store.observeRoom(id: id) }
        }
        .confirmationDialog("移除项目成员？", isPresented: Binding(
            get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }
        ), titleVisibility: .visible, presenting: memberToRemove) { member in
            Button("移除成员", role: .destructive) { change(.remove(member.id)) }
        } message: { member in
            Text("「\(member.name)」将失去项目访问权限，当前邀请码也会失效。")
        }
        .confirmationDialog("退出项目协作？", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("退出协作", role: .destructive) {
                Task {
                    if await store.changeRoom(.leave) { dismiss() }
                }
            }
        }
    }

    private var activeRoomID: String? {
        guard scenePhase == .active, store.project?.room != nil else { return nil }
        return store.project?.id
    }

    private func members(_ room: WebBuildRoom, canManage: Bool) -> some View {
        Section("成员 · \(room.members.count)/8") {
            ForEach(room.members) { member in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: member.name)
                        if member.id == "owner" { Text("所有者").font(.caption).foregroundStyle(.secondary) }
                        else if member.id == room.viewerId { Text("我").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if canManage, member.id != "owner" {
                        Button("移除", role: .destructive) { memberToRemove = member }
                            .buttonStyle(.borderless)
                            .disabled(store.isWorking)
                            .accessibilityLabel("移除\(member.name)")
                    }
                }
            }
        }
    }

    private func chat(_ room: WebBuildRoom) -> some View {
        Section("项目聊天") {
            if room.messages.isEmpty {
                Text("说说这个网页接下来怎么改。").foregroundStyle(.secondary)
            }
            ForEach(room.messages) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: item.author.id == room.viewerId ? "我" : item.author.name)
                        .font(.caption).foregroundStyle(.secondary)
                    if item.kind == .edit { Text("修改网页").font(.caption).foregroundStyle(.secondary) }
                    Text(verbatim: item.text).textSelection(.enabled)
                }
            }
            TextField("输入消息或网页修改要求", text: $message, axis: .vertical)
                .lineLimit(2...4)
                .disabled(store.isWorking)
            ViewThatFits(in: .horizontal) {
                HStack { chatActions }
                VStack(alignment: .leading) { chatActions }
            }
        }
    }

    @ViewBuilder private var chatActions: some View {
        Button("发送消息") {
            let text = message
            Task {
                if await store.changeRoom(.chat(text)), message == text { message = "" }
            }
        }
        .buttonStyle(.bordered)
        .disabled(store.isWorking || !WebBuildValue.text(message, limit: 600))
        Button("应用网页修改") {
            let text = message
            Task {
                if await store.update(.generate(text)), message == text { message = "" }
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.isWorking || !WebBuildValue.text(message, limit: 1000))
    }

    private func invitations(_ room: WebBuildRoom?) -> some View {
        Section {
            if let code = store.inviteCode {
                ShareLink(item: code) { Label("分享邀请码", systemImage: "square.and.arrow.up") }
            }
            if (room?.members.count ?? 1) < 8 {
                Button(room?.inviteExpiresAt == nil ? "生成邀请码" : "重新生成邀请码") { change(.invite) }
                    .disabled(store.isWorking)
            }
            if room?.inviteExpiresAt != nil {
                Button("撤销邀请码", role: .destructive) { change(.revoke) }
                    .disabled(store.isWorking)
            }
        } header: {
            Text("邀请成员")
        } footer: {
            Text("每个项目最多 8 人，含所有者。邀请码有效 24 小时，成员可查看共享草稿和项目聊天。")
        }
    }

    private func change(_ action: WebBuildRoomAction) {
        Task { await store.changeRoom(action) }
    }
}
