import SwiftUI

enum HomeEditSection: Hashable { case dock, main }

/// Springboard-style editing for the regular-size 云居 grid: icons wobble,
/// a badge removes an app (or dissolves a folder), and a short press-and-drag
/// moves things around.
///
/// As on the Home Screen, nothing moves while the finger travels: pausing on
/// the edge of an icon moves it aside, pausing on its centre makes a folder
/// (or adds to the folder under the finger).
///
/// The drag gesture lives on the whole canvas, not on each icon. The icon
/// under the finger is drawn as an overlay that follows it, so it can collect
/// more icons, or ride an auto-scroll when held near the top or bottom edge,
/// without its view ever being torn down. Icons join a drag either as on the
/// Home Screen (tap them with a second finger mid-drag) or one-handed: tap to
/// check them first, then drag any checked icon.
///
/// While a finger is down the new order lives only in `drag`; the library is
/// written once on release, so a drag never persists or schedules a sync per
/// step. Dropping onto the other section pins or unpins instead.
struct HomeEditCanvas: View {
    /// `nil` when the user hides 常用应用; an empty array shows a drop zone.
    let dock: [CloudApplication]?
    /// 我的应用: apps and folders in Home Screen order.
    let items: [HomeGridItem]
    /// Item keys that can move. Dock-only extras shown in 我的应用 (dock
    /// hidden) have no installed slot to move into.
    let reorderable: Set<String>
    let dockCapacity: Int
    let metrics: HomeGridMetrics
    /// Height of the visible scroll area, for the auto-scroll edge zones.
    let viewportHeight: CGFloat
    /// Brings off-screen rows into view while a drag waits at an edge.
    var scroller: HomeScroller?
    var reorderDock: ([String]) -> Void
    /// Reorders 我的应用 items; folders appear as `HomeLibrary.folderKey`.
    var reorderItems: ([String]) -> Void
    /// Pins or unpins several apps in one write; returns false when they don't fit.
    var setPinned: ([CloudApplication], Bool) -> Bool
    var remove: (CloudApplication) -> Void
    var createFolder: (_ name: String, _ keys: [String], _ anchor: String) -> Void
    var addToFolder: (_ folderID: String, _ keys: [String]) -> Void
    var dissolveFolder: (HomeFolder) -> Void
    var openFolder: (HomeFolder) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: DragState?
    @State private var tileFrames: [String: CGRect] = [:]
    /// After a move, hit-testing waits until the neighbours have settled:
    /// geometry reported mid-animation still shows the icon that just moved
    /// aside under the finger, which would move it straight back.
    @State private var settling = false
    @State private var settle: Task<Void, Never>?
    @State private var sectionFrames: [HomeEditSection: CGRect] = [:]
    /// The canvas's top in the scroll view's visible frame; it moves as the
    /// content scrolls, even while the finger holds still.
    @State private var originInViewport: CGFloat = 0
    @State private var edgeScroll: Task<Void, Never>?
    /// What the finger rests on, and the timer that acts on it after a pause.
    @State private var hover: Hover?
    @State private var dwell: Task<Void, Never>?
    @GestureState private var pressing = false
    /// Icons checked with a one-finger tap; dragging any of them carries all.
    @State private var selection: [String] = []
    @State private var selectionSection: HomeEditSection = .main
    @State private var dissolving: HomeFolder?
    @State private var pickups = 0
    @State private var swaps = 0
    @State private var rejections = 0
    @State private var landings = 0
    private static let space = "home.edit.canvas"
    private static let edgeZone: CGFloat = 72
    /// Pause before a neighbour moves aside, and before a folder forms.
    private static let moveDwell: UInt64 = 180_000_000
    private static let mergeDwell: UInt64 = 500_000_000

    private struct Hover: Equatable {
        let target: String
        /// The finger is on the target's centre: drop there to make or fill a folder.
        let merge: Bool
    }

    private struct DragState {
        let id = UUID()
        let originAtStart: CGFloat
        let primary: HomeGridItem
        let section: HomeEditSection
        let startCenter: CGPoint
        var translation: CGSize = .zero
        /// How far the content scrolled under the finger since pick-up.
        var scrollShift: CGFloat = 0
        /// Draft order of the section's item keys, without the stacked extras.
        var order: [String]
        /// Extra apps picked up with a second finger or by checking, in order.
        var stack: [CloudApplication] = []
        /// Target armed by a pause on its centre; dropping makes / fills a folder.
        var mergeTarget: String?
        var point: CGPoint {
            CGPoint(x: startCenter.x + translation.width, y: startCenter.y + translation.height + scrollShift)
        }
        var stackKeys: [String] { stack.map(\.homeKey) }
        var carriedApps: [CloudApplication] { (primary.app.map { [$0] } ?? []) + stack }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let dock { dockSection(dock) }
            mainSection
        }
        // Scroll target for "back to the top"; kept out of the layout flow.
        .background(alignment: .top) { Color.clear.frame(height: 1).id(HomeScroller.topID) }
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(HomeTileFrameKey.self) { tileFrames = $0 }
        .onPreferenceChange(HomeSectionFrameKey.self) { sectionFrames = $0 }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: HomeCanvasOriginKey.self,
                                   value: proxy.frame(in: .named(HomeScrollView<EmptyView>.viewport)).minY)
        })
        .onPreferenceChange(HomeCanvasOriginKey.self) { origin in
            originInViewport = origin
            // Content scrolled under a still finger: no touch event arrives,
            // so move the lifted icon and re-check what it hovers here.
            guard var current = drag else { return }
            current.scrollShift = current.originAtStart - origin
            drag = current
            follow(current.translation)
        }
        .overlay(alignment: .topLeading) { ghost }
        .simultaneousGesture(dragGesture)
        .onChange(of: pressing) { active in
            // A cancelled gesture (system interruption, scroll takeover) never
            // calls onEnded. Drop the draft without writing anything — but only
            // after a grace period: a normal release can reset the gesture
            // state before onEnded runs, and must still be committed.
            guard !active, let id = drag?.id else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if drag?.id == id { cancel() }
            }
        }
        .confirmationDialog("解散“\(dissolving?.name ?? "")”？",
                            isPresented: Binding(get: { dissolving != nil }, set: { if !$0 { dissolving = nil } }),
                            titleVisibility: .visible) {
            if let folder = dissolving {
                Button("解散文件夹", role: .destructive) {
                    withAnimation(Motion.standard(reduceMotion: reduceMotion)) { dissolveFolder(folder) }
                }
            }
        } message: { Text("其中的应用会留在云居原来的位置。") }
        .haptic(.impact, trigger: pickups)
        .haptic(.selection, trigger: swaps)
        .haptic(.warning, trigger: rejections)
        .haptic(.success, trigger: landings)
    }

    // MARK: Sections

    private var itemLookup: [String: HomeGridItem] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func visibleDock(_ apps: [CloudApplication]) -> [CloudApplication] {
        guard let drag, drag.section == .dock else { return apps }
        var lookup = Dictionary(apps.map { ($0.homeKey, $0) }, uniquingKeysWith: { first, _ in first })
        if let app = drag.primary.app { lookup[app.homeKey] = app }
        return drag.order.compactMap { lookup[$0] }
    }

    private var visibleItems: [HomeGridItem] {
        guard let drag, drag.section == .main else { return items }
        var lookup = itemLookup
        lookup[drag.primary.id] = drag.primary
        return drag.order.compactMap { lookup[$0] }
    }

    private func highlighted(_ section: HomeEditSection) -> Bool {
        guard let drag, drag.section != section else { return false }
        return sectionFrames[section]?.contains(drag.point) == true
    }

    private func dockSection(_ dock: [CloudApplication]) -> some View {
        let apps = visibleDock(dock)
        let lit = highlighted(.dock)
        return HomeDockPlatter {
            if apps.isEmpty {
                dropZone("拖到这里设为常用（最多 \(dockCapacity) 个）", highlighted: lit)
            } else {
                HomeDockRow(items: apps.map(HomeDockItem.init), metrics: metrics) { item in
                    tile(.app(item.app), in: .dock, siblings: apps.map(\.homeKey))
                        .transition(Motion.appear(reduceMotion: reduceMotion))
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: lit && !apps.isEmpty ? 2 : 0))
        .animation(Motion.fade, value: lit)
        .background(sectionFrameReader(.dock))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("常用应用")
        .zIndex(drag?.section == .dock ? 1 : 0)
    }

    private var mainSection: some View {
        let visible = visibleItems
        return VStack(alignment: .leading, spacing: 16) {
            Text("我的应用").font(.headline).accessibilityAddTraits(.isHeader)
            if visible.isEmpty {
                dropZone("拖到这里取消常用", highlighted: highlighted(.main))
            } else {
                LazyVGrid(columns: metrics.gridItems, spacing: HomeGridMetrics.rowSpacing) {
                    ForEach(visible) { item in
                        tile(item, in: .main, siblings: visible.map(\.id)).transition(Motion.appear(reduceMotion: reduceMotion))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(sectionFrameReader(.main))
        .zIndex(drag?.section == .main ? 1 : 0)
    }

    private func sectionFrameReader(_ section: HomeEditSection) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(key: HomeSectionFrameKey.self, value: [section: proxy.frame(in: .named(Self.space))])
        }
    }

    private func dropZone(_ hint: String, highlighted: Bool) -> some View {
        Text(hint)
            .font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: HomeGridMetrics.iconSize)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(highlighted ? Color.accentColor : Color(uiColor: .separator))
            )
            .animation(Motion.fade, value: highlighted)
    }

    // MARK: Tiles

    private func movable(_ key: String, in section: HomeEditSection) -> Bool {
        section == .dock || reorderable.contains(key)
    }

    private func reorderAction(_ section: HomeEditSection) -> ([String]) -> Void {
        section == .dock ? reorderDock : reorderItems
    }

    @ViewBuilder
    private func tile(_ item: HomeGridItem, in section: HomeEditSection, siblings: [String]) -> some View {
        let key = item.id
        let lifted = drag?.primary.id == key
        let canMove = movable(key, in: section)
        let merging = drag?.mergeTarget == key
        let base = Group {
            switch item {
            case .app(let app):
                let checked = selectionSection == section && selection.contains(key)
                HomeEditTile(key: key, name: app.name, showsName: section != .dock, labelWidth: metrics.labelWidth,
                             wobbling: !reduceMotion && !lifted, selected: checked, merging: merging, isUnavailable: app.isUnavailable == true,
                             remove: { remove(app) }) {
                    ApplicationIcon(application: app, size: HomeGridMetrics.iconSize)
                }
                .gesture(SpatialTapGesture().onEnded { tap in
                    if !onBadge(tap.location, showsName: section != .dock) { collect(app, from: section) }
                })
                .accessibilityLabel(app.name)
                .accessibilityAddTraits(checked ? .isSelected : [])
                .accessibilityAction(named: "从云居移除") { remove(app) }
                .modifier(HomeTilePinAction(section: section, dockAvailable: dock != nil,
                                            dockIsFull: (dock?.count ?? 0) >= dockCapacity) {
                    withAnimation(Motion.standard(reduceMotion: reduceMotion)) { _ = setPinned([app], section == .main) }
                })
            case .folder(let folder, let apps):
                HomeEditTile(key: key, name: folder.name, showsName: true, labelWidth: metrics.labelWidth,
                             wobbling: !reduceMotion && !lifted, selected: false, merging: merging,
                             remove: { dissolving = folder }) {
                    HomeFolderIcon(apps: apps)
                }
                // Tapping a folder while editing opens it, as on the Home Screen.
                .gesture(SpatialTapGesture().onEnded { tap in
                    if drag == nil && !onBadge(tap.location, showsName: true) { openFolder(folder) }
                })
                .accessibilityLabel("\(folder.name)，文件夹，\(apps.count) 个应用")
                .accessibilityAction(named: "打开") { openFolder(folder) }
                .accessibilityAction(named: "解散文件夹") { dissolving = folder }
            }
        }
        base
            .background(GeometryReader { proxy in
                Color.clear.preference(key: HomeTileFrameKey.self, value: [key: proxy.frame(in: .named(Self.space))])
            })
            .id(key)
            // The lifted icon is drawn by `ghost`; its slot stays as a gap.
            .opacity(lifted ? 0 : 1)
            .accessibilityHint(canMove ? "可用操作调整位置" : "")
            .accessibilityIdentifier("home.edit.tile.\(key)")
            .modifier(HomeTileMoveActions(enabled: canMove, keys: siblings, key: key, apply: reorderAction(section)))
    }

    /// The lifted icon (or folder), plus up to two collected icons fanned
    /// behind it and a count badge, following the finger.
    @ViewBuilder private var ghost: some View {
        if let drag {
            let behind = Array(drag.stack.suffix(2).reversed())
            ZStack(alignment: .topTrailing) {
                ZStack {
                    ForEach(Array(behind.enumerated()), id: \.element.homeKey) { index, app in
                        ApplicationIcon(application: app, size: HomeGridMetrics.iconSize)
                            .rotationEffect(.degrees(Double(index + 1) * 5))
                            .offset(x: CGFloat(index + 1) * 5, y: CGFloat(index + 1) * 3)
                    }
                    switch drag.primary {
                    case .app(let app): ApplicationIcon(application: app, size: HomeGridMetrics.iconSize)
                    case .folder(_, let apps): HomeFolderIcon(apps: apps)
                    }
                }
                if !drag.stack.isEmpty {
                    Text("\(drag.stack.count + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).frame(minWidth: 24, minHeight: 24)
                        .background(Color.accentColor, in: Capsule())
                        .offset(x: 10, y: -10)
                        .transition(.scale.combined(with: .opacity))
                        .numericTransition(Double(drag.stack.count + 1))
                }
            }
            .scaleEffect(reduceMotion ? 1 : (drag.mergeTarget == nil ? 1.1 : 0.9))
            .animation(Motion.press, value: drag.mergeTarget)
            .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
            .position(drag.point)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }

    // MARK: Dragging

    private var dragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.12)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)))
            .updating($pressing) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                guard case .second(true, let movement?) = value else { return }
                if drag == nil { begin(at: movement.startLocation) }
                follow(movement.translation)
            }
            .onEnded { _ in end() }
    }

    private func item(at point: CGPoint) -> (HomeGridItem, HomeEditSection)? {
        let candidates: [(HomeGridItem, HomeEditSection)] =
            (dock ?? []).map { (.app($0), .dock) } + items.map { ($0, .main) }
        return candidates.first { item, section in
            movable(item.id, in: section) && tileFrames[item.id]?.contains(point) == true
        }
    }

    private func begin(at location: CGPoint) {
        guard let (item, section) = item(at: location), let frame = tileFrames[item.id] else { return }
        let order = section == .dock ? (dock ?? []).map(\.homeKey) : items.map(\.id)
        // Track the icon's centre (names sit below it), keeping the offset
        // between finger and icon from the moment of pick-up.
        let center = CGPoint(x: frame.midX, y: frame.minY + HomeGridMetrics.iconSize / 2)
        var state = DragState(originAtStart: originInViewport, primary: item, section: section, startCenter: center, order: order)
        // Checked apps in the same section ride along with an app, in order.
        if item.app != nil, selectionSection == section {
            let apps = section == .dock ? (dock ?? []) : items.compactMap(\.app)
            let lookup = Dictionary(apps.map { ($0.homeKey, $0) }, uniquingKeysWith: { first, _ in first })
            state.stack = order.filter { $0 != item.id && selection.contains($0) }.compactMap { lookup[$0] }
            state.order.removeAll { key in state.stack.contains { $0.homeKey == key } }
        }
        settle?.cancel(); settling = false
        hover = nil
        withAnimation(Motion.press) {
            drag = state
            selection = []
        }
        pickups += 1
    }

    private func collect(_ app: CloudApplication, from section: HomeEditSection) {
        guard drag != nil else { toggleSelection(app, in: section); return }
        guard var current = drag, current.section == section, current.primary.app != nil, app.homeKey != current.primary.id,
              !current.stackKeys.contains(app.homeKey), movable(app.homeKey, in: section) else { return }
        current.stack.append(app)
        current.order.removeAll { $0 == app.homeKey }
        withAnimation(Motion.standard(reduceMotion: reduceMotion)) { drag = current }
        settleThenRecheck()
        pickups += 1
    }

    private func toggleSelection(_ app: CloudApplication, in section: HomeEditSection) {
        guard movable(app.homeKey, in: section) else { return }
        withAnimation(Motion.fade) {
            if selectionSection != section { selection = []; selectionSection = section }
            if let index = selection.firstIndex(of: app.homeKey) { selection.remove(at: index) }
            else { selection.append(app.homeKey) }
        }
        swaps += 1
    }

    /// Whether a tap (in tile coordinates) hit the remove badge. Which of two
    /// overlapping tap handlers wins isn't guaranteed, so a badge tap must
    /// never also check an app or open a folder over the confirmation.
    private func onBadge(_ location: CGPoint, showsName: Bool) -> Bool {
        let iconX = showsName ? (metrics.labelWidth - HomeGridMetrics.iconSize) / 2 : 0
        let badge = CGPoint(x: iconX + 4, y: 4)
        return hypot(location.x - badge.x, location.y - badge.y) <= 22
    }

    /// The icon area of a tile (the name sits below it).
    private func iconRect(_ key: String) -> CGRect? {
        guard let frame = tileFrames[key] else { return nil }
        let size = HomeGridMetrics.iconSize
        return CGRect(x: frame.midX - size / 2, y: frame.minY, width: size, height: size)
    }

    private func follow(_ translation: CGSize) {
        guard var current = drag else { return }
        current.translation = translation
        drag = current
        let point = current.point
        let key = current.primary.id
        if settling { return watchEdges(point) }
        let target = current.order.first { $0 != key && tileFrames[$0]?.insetBy(dx: 10, dy: 10).contains(point) == true }
        if let target, movable(target, in: current.section) {
            // Only apps make folders, and only in 我的应用; folders never nest.
            let canMerge = current.section == .main && current.primary.app != nil
            let onCentre = iconRect(target)?.insetBy(dx: 14, dy: 14).contains(point) == true
            setHover(Hover(target: target, merge: canMerge && onCentre))
        } else {
            setHover(nil)
        }
        watchEdges(point)
    }

    /// Acts on what the finger rests on once it has paused there: centre arms
    /// a folder, edge moves the neighbour aside. Moving on cancels both.
    private func setHover(_ next: Hover?) {
        guard next != hover else { return }
        hover = next
        dwell?.cancel(); dwell = nil
        if drag?.mergeTarget != nil, drag?.mergeTarget != next?.target || next?.merge != true {
            withAnimation(Motion.press) { drag?.mergeTarget = nil }
        }
        guard let next else { return }
        dwell = Task { @MainActor in
            try? await Task.sleep(nanoseconds: next.merge ? Self.mergeDwell : Self.moveDwell)
            guard !Task.isCancelled, hover == next, var current = drag,
                  // Re-check against today's geometry: the finger must still be there.
                  tileFrames[next.target]?.insetBy(dx: 10, dy: 10).contains(current.point) == true,
                  !next.merge || iconRect(next.target)?.insetBy(dx: 14, dy: 14).contains(current.point) == true
            else { return }
            if next.merge {
                current.mergeTarget = next.target
                withAnimation(Motion.press) { drag = current }
            } else if let to = current.order.firstIndex(of: next.target) {
                current.order = HomeEditOrder.moving(current.primary.id, in: current.order, to: to)
                current.mergeTarget = nil
                hover = nil
                withAnimation(Motion.standard(reduceMotion: reduceMotion)) { drag = current }
                settleThenRecheck()
            }
            swaps += 1
        }
    }

    /// Pauses hit-testing while the grid animates into its new order, then
    /// checks once more — a finger that stopped sends no further events.
    private func settleThenRecheck() {
        settling = true
        settle?.cancel()
        settle = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            settling = false
            if let drag { follow(drag.translation) }
        }
    }

    /// Holding a dragged icon near the top or bottom of the visible area
    /// brings the next row into view, one row at a time, until it moves away.
    private func watchEdges(_ point: CGPoint) {
        let y = point.y + originInViewport
        guard scroller != nil, drag != nil, y < Self.edgeZone || y > viewportHeight - Self.edgeZone else {
            edgeScroll?.cancel(); edgeScroll = nil; return
        }
        guard edgeScroll == nil else { return }
        edgeScroll = Task { @MainActor in
            while !Task.isCancelled, let current = drag {
                let y = current.point.y + originInViewport
                if y > viewportHeight - Self.edgeZone {
                    // The highest tile still below the visible area.
                    guard let next = tileFrames.filter({ $0.value.maxY + originInViewport > viewportHeight + 1 })
                        .min(by: { $0.value.minY < $1.value.minY }) else { break }
                    scroller?.reveal(next.key, at: .bottom)
                } else if y < Self.edgeZone {
                    // The lowest tile still above it, or the very top.
                    if let previous = tileFrames.filter({ $0.value.minY + originInViewport < -1 })
                        .max(by: { $0.value.maxY < $1.value.maxY }) {
                        scroller?.reveal(previous.key, at: .top)
                    } else if originInViewport < 0 {
                        scroller?.reveal(HomeScroller.topID, at: .top)
                    } else { break }
                } else { break }
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            edgeScroll = nil
        }
    }

    private func end() {
        edgeScroll?.cancel(); edgeScroll = nil
        dwell?.cancel(); dwell = nil
        hover = nil
        settle?.cancel(); settling = false
        guard let finished = drag else { return }
        let other: HomeEditSection = finished.section == .dock ? .main : .dock
        let carried = finished.carriedApps
        withAnimation(Motion.standard(reduceMotion: reduceMotion)) {
            if let target = finished.mergeTarget, let targetItem = itemLookup[target] {
                switch targetItem {
                case .folder(let folder, _):
                    addToFolder(folder.id, carried.map(\.homeKey))
                case .app(let app):
                    createFolder(HomeGridItem.suggestedFolderName(for: [app] + carried),
                                 [app.homeKey] + carried.map(\.homeKey), app.homeKey)
                }
                landings += 1
            } else if dock != nil, sectionFrames[other]?.contains(finished.point) == true {
                // Folders stay in 我的应用; only apps go to and from the dock.
                if !carried.isEmpty, finished.primary.app != nil, setPinned(carried, other == .dock) { landings += 1 }
                else { rejections += 1 }
            } else {
                let original = finished.section == .dock ? (dock ?? []).map(\.homeKey) : items.map(\.id)
                let final = HomeEditOrder.landing(finished.stackKeys, after: finished.primary.id, in: finished.order)
                if final != original { reorderAction(finished.section)(final) }
            }
            drag = nil
        }
    }

    private func cancel() {
        edgeScroll?.cancel(); edgeScroll = nil
        dwell?.cancel(); dwell = nil
        hover = nil
        settle?.cancel(); settling = false
        withAnimation(Motion.standard(reduceMotion: reduceMotion)) { drag = nil }
    }
}

/// One icon or folder in edit mode. It is deliberately not a Button: tapping
/// an app while editing only checks it, just like the Home Screen ignores it.
struct HomeEditTile<Icon: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let key: String
    let name: String
    let showsName: Bool
    let labelWidth: CGFloat
    let wobbling: Bool
    let selected: Bool
    /// Another icon rests on this one's centre: a drop makes / fills a folder.
    let merging: Bool
    var isUnavailable = false
    let remove: () -> Void
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        HomeAppGlyph(name: name, showsName: showsName, labelWidth: labelWidth, isUnavailable: isUnavailable) {
            TimelineView(.animation(minimumInterval: nil, paused: !wobbling || reduceMotion)) { context in
                icon()
                    .rotationEffect(.degrees(wobbling && !reduceMotion ? angle(at: context.date) : 0))
            }
            // The folder that will form. Reduce Motion reveals its outline
            // through opacity while the target icon keeps its original size.
            .background {
                RoundedRectangle(cornerRadius: HomeGridMetrics.iconSize * 0.26, style: .continuous)
                    .fill(.regularMaterial)
                    .scaleEffect(reduceMotion ? 1.25 : (merging ? 1.25 : 0.8))
                    .opacity(merging ? 1 : 0)
            }
            .scaleEffect(merging && !reduceMotion ? 0.85 : 1)
            .animation(reduceMotion ? Motion.fade : Motion.spring, value: merging)
            .overlay(alignment: .topLeading) {
                Button(action: remove) {
                    Image(systemName: "minus.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(uiColor: .systemGray))
                        .font(.system(size: 22, weight: .semibold))
                        // Smaller than 44pt on purpose, as on the system home
                        // screen: a larger target would swallow drags that start
                        // near the icon's corner. VoiceOver users get the
                        // remove / dissolve action on the tile instead.
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(x: -14, y: -14)
                .opacity(merging ? 0 : 1)
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                .accessibilityIdentifier("home.edit.remove.\(key)")
            }
            .overlay(alignment: .bottomTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .font(.system(size: 22, weight: .semibold))
                        .background(Circle().fill(Color(uiColor: .systemBackground)).padding(2))
                        .offset(x: 6, y: 6)
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .scaleEffect(selected && !reduceMotion ? 0.92 : 1)
            .animation(reduceMotion ? Motion.fade : Motion.press, value: selected)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
    }

    /// About ±1.6° at 3 Hz. The phase comes from the key so neighbours never
    /// move in lockstep, and stays stable across redraws.
    private func angle(at date: Date) -> Double {
        let seed = key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let phase = Double(seed % 628) / 100
        return sin(date.timeIntervalSinceReferenceDate * 2 * .pi * 3 + phase) * 1.6
    }
}

/// VoiceOver equivalents of dragging within a section.
private struct HomeTileMoveActions: ViewModifier {
    let enabled: Bool
    let keys: [String]
    let key: String
    let apply: ([String]) -> Void

    func body(content: Content) -> some View {
        if enabled, let index = keys.firstIndex(of: key) {
            content
                .accessibilityAction(named: "前移") { swap(index, index - 1) }
                .accessibilityAction(named: "后移") { swap(index, index + 1) }
        } else { content }
    }

    private func swap(_ from: Int, _ to: Int) {
        guard keys.indices.contains(to) else { return }
        var next = keys
        next.swapAt(from, to)
        apply(next)
    }
}

/// VoiceOver equivalent of dragging between 我的应用 and 常用应用.
private struct HomeTilePinAction: ViewModifier {
    let section: HomeEditSection
    let dockAvailable: Bool
    let dockIsFull: Bool
    let toggle: () -> Void

    func body(content: Content) -> some View {
        if section == .dock { content.accessibilityAction(named: "取消常用", toggle) }
        else if dockAvailable && !dockIsFull { content.accessibilityAction(named: "设为常用", toggle) }
        else { content }
    }
}

private struct HomeTileFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct HomeCanvasOriginKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct HomeSectionFrameKey: PreferenceKey {
    static var defaultValue: [HomeEditSection: CGRect] = [:]
    static func reduce(value: inout [HomeEditSection: CGRect], nextValue: () -> [HomeEditSection: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
