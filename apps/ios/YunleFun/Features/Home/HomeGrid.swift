import SwiftUI

/// Springboard metrics shared by the 云居 grid, dock and edit mode, so icons
/// keep their exact slots when jiggle mode starts.
///
/// The first and last columns sit on the layout margin, the same 16pt line as
/// the large title and section headers, and the remaining space is shared
/// evenly between icons. Centering icons inside equal columns instead pushed
/// the grid about 12pt inside the titles on every iPhone width.
struct HomeGridMetrics: Equatable {
    static let margin: CGFloat = 16
    static let iconSize: CGFloat = 64
    static let rowSpacing: CGFloat = 24

    /// Width between the two layout margins.
    let width: CGFloat
    let columns: Int
    let gap: CGFloat

    /// iPhone portrait gets the Home Screen's fixed four columns; regular width
    /// (iPad, large iPhones in landscape) adds columns as space allows.
    init(width: CGFloat, sizeClass: UserInterfaceSizeClass?) {
        let width = max(width, Self.iconSize * 4)
        let columns = sizeClass == .regular ? max(4, Int((width + 24) / (Self.iconSize + 24))) : 4
        self.width = width
        self.columns = columns
        gap = (width - CGFloat(columns) * Self.iconSize) / CGFloat(columns - 1)
    }

    /// Names may run a little past their icon, as on the Home Screen, but
    /// never into the neighbouring name or past the screen-edge margin.
    var labelWidth: CGFloat { Self.iconSize + min(gap - 8, 24) }

    var gridItems: [GridItem] {
        Array(repeating: GridItem(.fixed(Self.iconSize), spacing: gap, alignment: .top), count: columns)
    }
}

/// Icon plus a single-line caption, like a Home Screen app. Names truncate
/// instead of wrapping so every row lines up; VoiceOver still reads the full
/// name from the enclosing control.
struct HomeAppGlyph<Icon: View>: View {
    let name: String
    var showsName = true
    var labelWidth: CGFloat = HomeGridMetrics.iconSize
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        VStack(spacing: 6) {
            icon()
            if showsName {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: labelWidth)
            }
        }
    }
}

/// Dock icons share the grid's column positions: four pinned apps line up
/// with the columns below, fewer sit centred with the same spacing.
struct HomeDockRow<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    let metrics: HomeGridMetrics
    @ViewBuilder var tile: (Item) -> Tile

    var body: some View {
        HStack(spacing: metrics.gap) {
            ForEach(items) { item in tile(item).frame(width: HomeGridMetrics.iconSize) }
        }
        .frame(maxWidth: .infinity)
    }
}

struct HomeDockItem: Identifiable {
    let app: CloudApplication
    var id: String { app.homeKey }
}

/// The 常用应用 row drawn as a dock: one row inside a rounded platter that
/// reaches slightly into the margins so its icons stay on the grid's columns.
/// Uses Liquid Glass where available (it already honours Reduce
/// Transparency) and a system material before that.
struct HomeDockPlatter<Content: View>: View {
    static var inset: CGFloat { 10 }
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        Group {
            if #available(iOS 26, *) {
                padded.glassEffect(.regular, in: shape)
            } else {
                padded.background(.regularMaterial, in: shape)
            }
        }
        .padding(.horizontal, -Self.inset)
    }

    private var padded: some View {
        content().padding(.horizontal, Self.inset).padding(.vertical, 14)
    }
}

/// The scroll view that hosts 云居. Its frame is the "viewport" coordinate
/// space, so a drag can tell how close the finger is to the visible top or
/// bottom edge, and the scroller lets a drag bring the next row into view.
struct HomeScrollView<Content: View>: View {
    static var viewport: String { "home.viewport" }
    @ViewBuilder var content: (_ scroller: HomeScroller) -> Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { content(HomeScroller(proxy: proxy)) }
                .coordinateSpace(name: Self.viewport)
        }
    }
}

/// Scrolls 云居 so a given tile (or the top of the page) comes into view.
struct HomeScroller {
    static let topID = "home.edit.top"
    let proxy: ScrollViewProxy

    func reveal(_ id: String, at anchor: UnitPoint) {
        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(id, anchor: anchor) }
    }
}

/// Pure order operations behind dragging, kept separate so they are unit tested.
enum HomeEditOrder {
    /// Moves `key` so it ends at `index` in the result (clamped).
    static func moving(_ key: String, in order: [String], to index: Int) -> [String] {
        guard let from = order.firstIndex(of: key) else { return order }
        var next = order
        next.remove(at: from)
        next.insert(key, at: min(max(0, index), next.count))
        return next
    }

    /// Final order after a drop: stacked apps land right after the one under
    /// the finger, in the order they were picked up.
    static func landing(_ stack: [String], after primary: String, in order: [String]) -> [String] {
        var next = order.filter { !stack.contains($0) }
        guard let index = next.firstIndex(of: primary) else { return order }
        next.insert(contentsOf: stack, at: index + 1)
        return next
    }

}

/// One cell of 我的应用: an app, or a folder standing where its first member is.
enum HomeGridItem: Identifiable {
    case app(CloudApplication)
    case folder(HomeFolder, [CloudApplication])

    var id: String {
        switch self {
        case .app(let app): return app.homeKey
        case .folder(let folder, _): return HomeLibrary.folderKey(folder.id)
        }
    }
    var name: String {
        switch self {
        case .app(let app): return app.name
        case .folder(let folder, _): return folder.name
        }
    }
    var app: CloudApplication? { if case .app(let app) = self { return app } else { return nil } }

    /// Groups the ordered apps into grid items. Members of a folder collapse
    /// into one folder cell at the first member's position.
    static func items(_ apps: [CloudApplication], folders: [HomeFolder]) -> [HomeGridItem] {
        let lookup = Dictionary(apps.map { ($0.homeKey, $0) }, uniquingKeysWith: { first, _ in first })
        var folderOf: [String: HomeFolder] = [:]
        for folder in folders { for key in folder.appIds where folderOf[key] == nil { folderOf[key] = folder } }
        var emitted = Set<String>()
        var items: [HomeGridItem] = []
        for app in apps {
            if let folder = folderOf[app.homeKey] {
                guard emitted.insert(folder.id).inserted else { continue }
                let members = folder.appIds.compactMap { lookup[$0] }
                items.append(.folder(folder, members))
            } else {
                items.append(.app(app))
            }
        }
        return items
    }

    /// Suggested name for a new folder: the members' shared category, as the
    /// Home Screen does, otherwise the generic name.
    static func suggestedFolderName(for apps: [CloudApplication]) -> String {
        let categories = Set(apps.map(\.browseCategory))
        if categories.count == 1, let category = categories.first, !category.isEmpty, category != "全部" { return category }
        return "文件夹"
    }
}

/// A folder's Home Screen icon: a frosted rounded square previewing up to
/// nine members in a 3 × 3 grid.
struct HomeFolderIcon: View {
    let apps: [CloudApplication]
    var size: CGFloat = HomeGridMetrics.iconSize

    var body: some View {
        let inset = size * 0.14, spacing = size * 0.06
        let mini = (size - inset * 2 - spacing * 2) / 3
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(mini), spacing: spacing), count: 3), spacing: spacing) {
            ForEach(apps.prefix(9), id: \.homeKey) { app in
                ApplicationIcon(application: app, size: mini)
            }
        }
        .padding(inset)
        .frame(width: size, height: size, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).strokeBorder(.quaternary, lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
