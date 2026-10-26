import SwiftUI

/// Identifies the folder a sheet shows; the folder itself is always re-read
/// from the library so renames and membership changes appear live.
struct HomeFolderSelection: Identifiable, Hashable {
    let id: String
}

/// An open folder. Browsing is a grid like 云居; 整理 switches to the system
/// list so apps can be reordered or moved out with standard controls.
struct HomeFolderView: View {
    let folderID: String
    @EnvironmentObject private var library: HomeLibrary
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var runtime: NativeWebRuntime
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var editing = false
    @State private var renaming = false
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool
    @State private var confirmDissolve = false

    private var folder: HomeFolder? { library.snapshot.configuration.folders.first { $0.id == folderID } }
    private var apps: [CloudApplication] {
        (folder?.appIds ?? []).map { key in
            let app = library.snapshot.application(reference: key)
            return app.refreshingPublicMetadata(with: catalog.application(id: app.id))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Renaming happens in place, like a Home Screen folder's title.
                if renaming { nameField }
                if editing || dynamicTypeSize.isAccessibilitySize { list } else { grid }
            }
            .navigationTitle(folder?.name ?? "文件夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }.accessibilityIdentifier("home.folder.close")
                }
                ToolbarItem(placement: .primaryAction) {
                    if renaming {
                        Button("完成", action: commitName).accessibilityIdentifier("home.folder.rename.done")
                    } else if editing {
                        Button("完成") { withAnimation(Motion.fade) { editing = false } }
                            .accessibilityIdentifier("home.folder.done")
                    } else {
                        Menu {
                            Button {
                                draftName = folder?.name ?? ""
                                withAnimation(Motion.fade) { renaming = true }
                                nameFocused = true
                            } label: { Label("重命名", systemImage: "pencil") }
                            Button { withAnimation(Motion.fade) { editing = true } } label: {
                                Label("整理", systemImage: "arrow.up.arrow.down")
                            }
                            Button(role: .destructive) { confirmDissolve = true } label: {
                                Label("解散文件夹", systemImage: "folder.badge.minus")
                            }
                        } label: { Label("文件夹选项", systemImage: "ellipsis").labelStyle(.iconOnly) }
                        .accessibilityIdentifier("home.folder.options")
                    }
                }
            }
            .confirmationDialog("解散“\(folder?.name ?? "文件夹")”？", isPresented: $confirmDissolve, titleVisibility: .visible) {
                Button("解散文件夹", role: .destructive) { library.dissolveFolder(folderID) }
            } message: { Text("其中的应用会留在云居原来的位置。") }
        }
        .presentationDetents([.medium, .large])
        // The folder was dissolved or emptied, here or by sync.
        .onChange(of: folder == nil) { if $0 { dismiss() } }
    }

    private var nameField: some View {
        HomeFolderNameField(text: $draftName)
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
            .submitLabel(.done)
            .focused($nameFocused)
            .onSubmit(commitName)
            .onChange(of: draftName) { if $0.count > HomeFolder.nameLimit { draftName = String($0.prefix(HomeFolder.nameLimit)) } }
            .padding(.vertical, 10).padding(.horizontal, 16)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, HomeGridMetrics.margin).padding(.top, 12)
            .transition(.opacity)
    }

    private func commitName() {
        library.renameFolder(folderID, to: draftName)
        nameFocused = false
        withAnimation(Motion.fade) { renaming = false }
    }

    private var grid: some View {
        GeometryReader { proxy in
            let metrics = HomeGridMetrics(width: proxy.size.width - 2 * HomeGridMetrics.margin, sizeClass: sizeClass)
            ScrollView {
                LazyVGrid(columns: metrics.gridItems, spacing: HomeGridMetrics.rowSpacing) {
                    ForEach(apps, id: \.homeKey) { app in
                        Button { open(app) } label: {
                            HomeAppGlyph(name: app.name, labelWidth: metrics.labelWidth, isUnavailable: app.isUnavailable == true) {
                                ApplicationIcon(application: app, size: HomeGridMetrics.iconSize)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("打开\(app.name)")
                        .accessibilityValue(app.accessLabel ?? "")
                        .accessibilityIdentifier("home.folder.app.\(app.homeKey)")
                        .contextMenu {
                            Button { withAnimation(Motion.fade) { library.removeFromFolder(app.homeKey) } } label: {
                                Label("移出文件夹", systemImage: "arrow.up.forward.square")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(HomeGridMetrics.margin)
                .animation(Motion.fade, value: folder?.appIds ?? [])
            }
        }
    }

    private var list: some View {
        List {
            ForEach(apps, id: \.homeKey) { app in
                if editing {
                    ApplicationRow(application: app)
                } else {
                    Button { open(app) } label: { ApplicationRow(application: app).foregroundStyle(.primary) }
                }
            }
            .onMove { offsets, destination in
                guard let folder else { return }
                var ids = folder.appIds
                ids.move(fromOffsets: offsets, toOffset: destination)
                library.reorderFolder(folderID, appIds: ids)
            }
            .onDelete { offsets in
                guard let folder else { return }
                offsets.map { folder.appIds[$0] }.forEach(library.removeFromFolder)
            }
            .deleteDisabled(!editing)
            .moveDisabled(!editing)
        }
        .environment(\.editMode, .constant(editing ? .active : .inactive))
    }

    /// Close the sheet first so the app opens over 云居, not over the folder.
    private func open(_ app: CloudApplication) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { runtime.open(app, catalog: catalog, library: library) }
    }
}

/// The rename field, with the standard trailing clear button.
private struct HomeFolderNameField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            // Label and identifier go on the field itself: set on the stack they
            // would also overwrite the clear button's.
            TextField("文件夹名称", text: $text)
                .accessibilityLabel("文件夹名称")
                .accessibilityIdentifier("home.folder.name")
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除名称")
                .accessibilityIdentifier("home.folder.name.clear")
            }
        }
    }
}
