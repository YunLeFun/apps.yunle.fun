import SwiftUI

struct WebProfileRecoveryView: View {
    let application: CloudApplication
    @EnvironmentObject private var runtime: NativeWebRuntime
    @EnvironmentObject private var accounts: AccountStore
    @State private var snapshot: NativeWebRuntime.ProfileRecoverySnapshot?
    @State private var selected: WebProfileRepository.Selection?
    @State private var error: String?
    @State private var restored = false
    private struct Choice: Identifiable {
        let index: Int
        let profile: WebProfileRepository.Selection
        var id: UUID { profile.identifier }
    }
    private var choices: [Choice] {
        guard let snapshot else { return [] }
        return snapshot.profiles.retained.enumerated().map { Choice(index: $0.offset, profile: $0.element) }.reversed()
    }

    var body: some View {
        List {
            Section {
                Text("这里保存着当前账号之前使用\(application.name)时留下的本机数据。选择一份后，下次打开应用会使用它，当前数据也会保留。")
                    .foregroundStyle(.secondary)
                Text("应用内尚未保存的编辑请先保存。应用可能需要重新登录，云端内容以应用自身的同步规则为准。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .accessibilityIdentifier("web-profiles.error")
                    Button("重新读取", action: load)
                }
            } else if let snapshot {
                if restored {
                    Section { Label("已切换应用数据，重新打开应用即可查看。", systemImage: "checkmark.circle") }
                }
                if snapshot.profiles.retained.isEmpty {
                    Section { Text("当前账号没有其他保留的数据。") }
                } else {
                    Section {
                        ForEach(choices) { choice in
                            Button { selected = choice.profile } label: {
                                Label("保留记录 \(choice.index + 1)", systemImage: "archivebox")
                            }
                            .accessibilityHint("确认后使用这份数据，当前数据仍会保留")
                            .accessibilityIdentifier("web-profiles.restore.\(choice.index)")
                        }
                    } header: { Text("保留的数据") }
                    footer: { Text("每条记录都是一份独立保留的数据，可切换后打开应用核对。") }
                }
            }
        }
        .navigationTitle("应用数据")
        .navigationBarTitleDisplayMode(.inline)
        .runtimeMenuToolbar()
        .onAppear(perform: load)
        .onChange(of: accounts.identityGeneration) { _ in selected = nil; restored = false; load() }
        .alert("使用这份数据？", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
               presenting: selected) { profile in
            Button("使用此数据") { restore(profile) }
            Button("取消", role: .cancel) { selected = nil }
        } message: { _ in
            Text("当前打开的应用会关闭。当前数据会保留，不会与这份数据合并；重新打开后可在应用内查看。")
        }
    }

    private func load() {
        do { snapshot = try runtime.profileRecovery(for: application); error = nil }
        catch {
            snapshot = nil
            self.error = accounts.user?.isUsable == true
                ? "暂时无法读取应用数据，原数据仍保留。请稍后重试。"
                : "请先登录原账号，再查看它保存的应用数据。"
        }
    }

    private func restore(_ profile: WebProfileRepository.Selection) {
        guard let snapshot else { return }
        do {
            try runtime.restoreWebProfile(profile, from: snapshot)
            selected = nil; restored = true; load()
        } catch {
            selected = nil
            self.error = "账号或应用数据已变化，未执行本次切换。请重新读取后再试。"
        }
    }
}
