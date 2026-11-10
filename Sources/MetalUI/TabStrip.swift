import MetalUICore
import MetalUILayout

// `TabStrip`: a closable, reorderable tab strip for an editor's file panel (Alloy gap G4, record 238, prefix `TBS-`, see
// `docs/superpowers/2026-11-07-tab-strip-decisions.md`). MetalUI-only (class M): SwiftUI's `TabView` is a page switcher and has
// no closable strip. Built from existing views: a horizontal `ProposalScrollView` in a `ScrollViewReader`, one `Component` per
// tab, gestures for select, middle-click close and drag reorder.

/// One tab of a ``TabStrip``: what it shows and whether it can be closed.
///
/// A value, so a strip compares equal to its last build while the items do (``TabStrip`` is `Equatable` over its data).
public struct TabStripItem<ID: Hashable> {
    /// The tab's identity: what `selection` holds when it is selected and what ``TabStrip/onCloseTab(_:)`` is called with.
    public var id: ID
    /// The title, shown on one line and truncated at the tail when the tab reaches its maximum width.
    public var title: String
    /// A small leading image, drawn at 14 points in the tab's foreground; `nil` shows none.
    public var icon: Image?
    /// Whether the file has unsaved edits. A dirty tab shows a dot in its close slot while the pointer is away, and the
    /// close button while it is over the tab; a non-closable dirty tab keeps the dot.
    public var isDirty: Bool
    /// Whether the tab has a close button and answers a middle click.
    public var isClosable: Bool
    /// A colour drawn as a short bar before the title, for example the colour of the session that changed the file; `nil`
    /// draws none.
    public var accent: Color?
    /// The accessibility identifier of the tab's button, as `.accessibilityIdentifier(_:)` on it would set (AppKit
    /// `AXIdentifier`, AccessKit `author_id`), for a test or automation client to find the tab by; `nil` sets none. Never
    /// derived from ``id`` (`TBS-J`).
    public var accessibilityIdentifier: String?
    /// The accessibility identifier of the tab's close button, set the same way; `nil` sets none (`TBS-J`).
    public var closeAccessibilityIdentifier: String?

    /// A tab identified by `id` and titled `title`, with the optional accessibility identifiers of its button and of its
    /// close button.
    public init(id: ID, title: String, icon: Image? = nil, isDirty: Bool = false, isClosable: Bool = true,
                accent: Color? = nil, accessibilityIdentifier: String? = nil,
                closeAccessibilityIdentifier: String? = nil) {
        self.accessibilityIdentifier = accessibilityIdentifier
        self.closeAccessibilityIdentifier = closeAccessibilityIdentifier
        self.id = id
        self.title = title
        self.icon = icon
        self.isDirty = isDirty
        self.isClosable = isClosable
        self.accent = accent
    }

    /// Whether `other` draws and behaves as this item does (the icon by what it draws, bitmaps by texture identity).
    @MainActor func isSame(as other: TabStripItem<ID>) -> Bool {
        guard id == other.id, title == other.title, isDirty == other.isDirty, isClosable == other.isClosable,
              accent == other.accent, accessibilityIdentifier == other.accessibilityIdentifier,
              closeAccessibilityIdentifier == other.closeAccessibilityIdentifier else { return false }
        switch (icon, other.icon) {
        case (nil, nil): return true
        case (let a?, let b?): return a.isSameDrawing(as: b)
        default: return false
        }
    }
}

/// The measures of a tab strip, in points.
enum TabStripMetrics {
    static let barHeight: Float = 32
    static let minTabWidth: Float = 96
    static let maxTabWidth: Float = 220
    static let closeSlot: Float = 18
    static let iconSide: Float = 14
    /// A drag shorter than this begins nothing: a click stays a click.
    static let dragSlop: Float = 4
}

/// One tab's width: its content's natural width clamped to the strip's minimum and maximum, whatever the proposal, with the
/// content laid out at that width so a long title truncates (a flexible frame under an unspecified proposal would clamp the
/// frame and let the title overflow it).
struct TabStripWidthLayout: ProposalLayout {
    static func width(natural: Double) -> Double {
        Swift.min(Swift.max(natural, Double(TabStripMetrics.minTabWidth)), Double(TabStripMetrics.maxTabWidth))
    }

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        guard !subviews.isEmpty else { return LayoutMeasurement(size: SizeD(width: Double(TabStripMetrics.minTabWidth), height: 0)) }
        let natural = subviews[0].sizeThatFits(ProposedSize(width: nil, height: proposal.height)).size.width
        let width = Self.width(natural: natural)
        let height = subviews[0].sizeThatFits(ProposedSize(width: width, height: proposal.height)).size.height
        return LayoutMeasurement(size: SizeD(width: width, height: height))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        guard !subviews.isEmpty else { return }
        subviews[0].place(at: Point(x: bounds.x, y: bounds.y), anchor: .topLeading,
                          proposal: ProposedSize(width: bounds.width, height: bounds.height))
    }
}

/// Which side of a tab the drop marker is drawn on.
enum TabStripDropEdge { case leading, trailing }

/// What a strip remembers about a drag in progress: the tab, and how far the pointer has moved along the strip.
struct TabStripDrag<ID: Hashable> {
    var id: ID
    var translation: Float
}

/// A closable, reorderable tab strip: the tabs of an editor's file panel (MetalUI-only, class M; Alloy gap G4).
///
/// ```swift
/// TabStrip(selection: $openFile, tabs: files.map {
///     TabStripItem(id: $0.id, title: $0.name, isDirty: $0.isEdited, accent: $0.sessionColor)
/// })
/// .onCloseTab { id in close(id) }
/// .onMoveTab { from, to in files.move(from: from, to: to) }
/// ```
///
/// **The strip owns the look and the pointer, the app owns the data and the keys.** A click on a tab writes `selection`; the
/// close button (× on a hovered or selected tab, the dirty dot while the pointer is away) and a middle click call
/// ``onCloseTab(_:)`` and change nothing else (the app removes the tab and moves `selection`); a drag past a few points
/// reorders and calls ``onMoveTab(_:)`` once, at the release. No key is bound: ⌃Tab, ⌘1–9 and ⌘W are the app's, through
/// `onKeyPress` or the keymap, writing `selection`.
///
/// **Overflow.** A tab keeps its natural width between 96 and 220 points (a longer title truncates at the tail) and the strip
/// scrolls sideways when the tabs are wider than it. A vertical wheel over the strip scrolls the page beneath, not the strip
/// (`XS-F`); a trackpad's sideways swipe scrolls the strip. The selected tab is scrolled into view whenever `selection`
/// changes, by the app or by a click, and once on appearing.
///
/// **Look.** The bar is `.surfaceSecondary`; the selected tab is `.background` (the colour of the panel under it), the others
/// show a faint wash while hovered. Hairlines in `.separator` close each tab and the bar's lower edge. The dragged tab dims and
/// an `.accent` bar marks where it would land.
///
/// **Accessibility.** The strip is a group labelled "Tabs"; each tab is a button labelled with its title, selected when it
/// is, with the value "edited" when dirty, and pressing it selects. A closable tab has a second button labelled
/// "Close <title>" beside it.
///
/// The strip is `Equatable` over its data (the selection, the items' fields), so `.equatable()` replays it while nothing
/// changed; **the closures are not compared**, as `MarkdownView` does not compare its highlighter's calls: a handler that
/// captures changing state should read it from a model, not capture a copy.
public struct TabStrip<ID: Hashable>: Component, @MainActor Equatable {
    var selection: Binding<ID>
    var tabs: [TabStripItem<ID>]
    var closeHandler: (@MainActor (ID) -> Void)?
    var moveHandler: (@MainActor (Int, Int) -> Void)?
    /// Each tab's laid-out width, written from `onGeometryChange` (a lifecycle action, never a phase): a drag finds the
    /// tab under the pointer from them.
    @State private var widths: [ID: Float] = [:]
    /// The drag in progress, written from the gesture's input.
    @State private var drag: TabStripDrag<ID>?

    /// A strip showing `tabs`, with the one whose id `selection` holds drawn selected.
    public init(selection: Binding<ID>, tabs: [TabStripItem<ID>]) {
        self.selection = selection
        self.tabs = tabs
    }

    /// Runs `action` with a tab's id when its close button is pressed or it is middle-clicked. The strip removes nothing and
    /// moves no selection: the app does both.
    public func onCloseTab(_ action: @escaping @MainActor (ID) -> Void) -> TabStrip<ID> {
        var copy = self
        copy.closeHandler = action
        return copy
    }

    /// Runs `action(from, to)` when a drag moves a tab: `from` is its index before, `to` the index it has after the move
    /// (`array.insert(array.remove(at: from), at: to)`), never equal to `from`. Called once, at the release.
    public func onMoveTab(_ action: @escaping @MainActor (_ from: Int, _ to: Int) -> Void) -> TabStrip<ID> {
        var copy = self
        copy.moveHandler = action
        return copy
    }

    /// The index tab `from` would take if released with its pointer moved `translation` points along the strip, from the
    /// recorded widths: the number of other tabs whose middle lies left of the dragged tab's middle.
    static func destination(from: Int, translation: Float, tabs: [TabStripItem<ID>], widths: [ID: Float]) -> Int {
        guard tabs.indices.contains(from) else { return from }
        var x: Float = 0
        var mids: [Float] = []
        for tab in tabs {
            let w = widths[tab.id] ?? 0
            mids.append(x + w / 2)
            x += w
        }
        let centre = mids[from] + translation
        var to = 0
        for (index, mid) in mids.enumerated() where index != from && mid < centre { to += 1 }
        return to
    }

    /// The strip: a bar of tabs in a horizontal scroller over a rule (`TBS-B`).
    public var content: some ElementGroup {
        let tabs = tabs, selection = selection, closeHandler = closeHandler, moveHandler = moveHandler
        let selected = selection.wrappedValue
        let drag = drag
        let widths = $widths
        let dragBinding = $drag
        let target = drag.flatMap { current in
            tabs.firstIndex { $0.id == current.id }.map { from in
                (from: from, to: Self.destination(from: from, translation: current.translation, tabs: tabs,
                                                  widths: widths.wrappedValue))
            }
        }
        return VStack(spacing: Pixels(0)) {
            ScrollViewReader { proxy in
                ProposalScrollView(.horizontal) {
                    HStack(spacing: Pixels(0)) {
                        ForEach(Array(tabs.enumerated()), id: \.element.id) { index, item in
                            TabStripTab(
                                item: item, isSelected: item.id == selected,
                                isDragSource: drag?.id == item.id,
                                dropEdge: Self.dropEdge(index: index, target: target),
                                select: { selection.wrappedValue = item.id },
                                close: { closeHandler?(item.id) },
                                width: { widths.wrappedValue[item.id] = $0 },
                                dragChanged: { dragBinding.wrappedValue = TabStripDrag(id: item.id, translation: $0) },
                                dragEnded: { translation in
                                    dragBinding.wrappedValue = nil
                                    guard let from = tabs.firstIndex(where: { $0.id == item.id }) else { return }
                                    let to = Self.destination(from: from, translation: translation, tabs: tabs,
                                                              widths: widths.wrappedValue)
                                    if to != from { moveHandler?(from, to) }
                                },
                                dragCancelled: { dragBinding.wrappedValue = nil })
                        }
                    }
                }
                .scrollIndicators(.never)
                .onChange(of: selected, initial: true) { proxy.scrollTo(selected) }
            }
            .frame(height: Pixels(TabStripMetrics.barHeight - 1))
            Color(.separator).frame(height: Pixels(1))
        }
        .frame(height: Pixels(TabStripMetrics.barHeight))
        .background(.surfaceSecondary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
    }

    /// Which side of tab `index` the drop marker is drawn on, if any: the leading edge of the destination when the dragged
    /// tab moves left, its trailing edge when it moves right.
    static func dropEdge(index: Int, target: (from: Int, to: Int)?) -> TabStripDropEdge? {
        guard let target, target.to != target.from, index == target.to else { return nil }
        return target.to < target.from ? .leading : .trailing
    }

    public static func == (l: TabStrip<ID>, r: TabStrip<ID>) -> Bool {
        guard l.selection.wrappedValue == r.selection.wrappedValue, l.tabs.count == r.tabs.count else { return false }
        for (a, b) in zip(l.tabs, r.tabs) where !a.isSame(as: b) { return false }
        return true
    }
}

/// One tab: a selectable body, a close slot, and the gestures that act on the whole tab.
struct TabStripTab<ID: Hashable>: Component {
    let item: TabStripItem<ID>
    let isSelected: Bool
    let isDragSource: Bool
    let dropEdge: TabStripDropEdge?
    let select: @MainActor () -> Void
    let close: @MainActor () -> Void
    let width: @MainActor (Float) -> Void
    let dragChanged: @MainActor (Float) -> Void
    let dragEnded: @MainActor (Float) -> Void
    let dragCancelled: @MainActor () -> Void
    @State private var isHovered = false
    @State private var tabWidth: Float = 0

    var content: some ElementGroup {
        let isSelected = isSelected, isHovered = isHovered, hover = $isHovered, size = $tabWidth, tabWidth = tabWidth
        let item = item, close = close, width = width
        let dragChanged = dragChanged, dragEnded = dragEnded, dragCancelled = dragCancelled
        let ink = isSelected ? Color(.textPrimary) : Color(.textPrimary).opacity(0.64)
        let fill = isSelected ? Color(.background) : (isHovered ? Color(.textPrimary).opacity(0.06) : Color.clear)
        return TabStripWidthLayout()() {
            HStack(spacing: Pixels(0)) {
                TabStripLabel(item: item, isSelected: isSelected, select: select)
                if item.isClosable || item.isDirty {
                    TabStripCloseSlot(item: item, showsClose: item.isClosable && (isHovered || isSelected),
                                      showsDot: item.isDirty && !(item.isClosable && isHovered), close: close)
                }
            }
        }
        .foregroundStyle(ink)
        .frame(height: Pixels(TabStripMetrics.barHeight - 1))
        .background(fill)
        .overlay(alignment: .trailing) { Color(.separator).frame(width: Pixels(1)) }
        .overlay(alignment: dropEdge == .leading ? .leading : .trailing) {
            if dropEdge != nil { Color(.accent).frame(width: Pixels(2)) }
        }
        .opacity(isDragSource ? 0.5 : 1)
        .onHover { hover.wrappedValue = $0 }
        .gesture(DragGesture(minimumDistance: Pixels(TabStripMetrics.dragSlop))
            .onChanged { dragChanged($0.translation.width.value) }
            .onEnded { dragEnded($0.translation.width.value) }
            .onCancelled { dragCancelled() })
        .gesture(DragGesture(minimumDistance: Pixels(0), button: .middle)
            .onEnded { value in
                let inside = value.location.x.value >= 0 && value.location.x.value <= tabWidth
                    && value.location.y.value >= 0 && value.location.y.value <= TabStripMetrics.barHeight
                if item.isClosable && inside { close() }
            })
        .onGeometryChange(for: Float.self, of: { $0.size.width.value }, action: { measured in
            size.wrappedValue = measured
            width(measured)
        })
    }
}

/// The selectable part of a tab: accent bar, icon and title.
struct TabStripLabel<ID: Hashable>: Component {
    let item: TabStripItem<ID>
    let isSelected: Bool
    let select: @MainActor () -> Void

    var content: some ElementGroup {
        let item = item, select = select
        let body = HStack(spacing: Pixels(6)) {
            if let accent = item.accent {
                accent.frame(width: Pixels(3), height: Pixels(14))
            }
            if let icon = item.icon {
                icon.frame(width: Pixels(TabStripMetrics.iconSide), height: Pixels(TabStripMetrics.iconSide))
            }
            ProposalText(item.title).font(family: nil, size: 12).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: Pixels(0))
        }
        .padding(Edges(top: Pixels(0), right: Pixels(2), bottom: Pixels(0), left: Pixels(10)))
        .frame(maxWidth: Pixels.infinity, maxHeight: Pixels.infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { select() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select() }
        return VStack(spacing: Pixels(0)) {
            if let identifier = item.accessibilityIdentifier {
                if item.isDirty { body.accessibilityIdentifier(identifier).accessibilityValue("edited") }
                else { body.accessibilityIdentifier(identifier) }
            } else {
                if item.isDirty { body.accessibilityValue("edited") } else { body }
            }
        }
    }
}

/// The close slot: the dirty dot, or the close button.
struct TabStripCloseSlot<ID: Hashable>: Component {
    let item: TabStripItem<ID>
    let showsClose: Bool
    let showsDot: Bool
    let close: @MainActor () -> Void
    @State private var isHovered = false

    var content: some ElementGroup {
        let showsClose = showsClose, showsDot = showsDot, isHovered = isHovered, item = item, close = close
        let hover = $isHovered
        let body = ZStack {
            if showsDot {
                Circle().fill(Color(.textPrimary).opacity(0.7)).frame(width: Pixels(8), height: Pixels(8))
            } else if showsClose {
                Image(systemName: "xmark")
                    .frame(width: Pixels(16), height: Pixels(16))
                    .background(isHovered ? Color(.textPrimary).opacity(0.12) : Color.clear)
            }
        }
        .frame(width: Pixels(TabStripMetrics.closeSlot), height: Pixels(TabStripMetrics.barHeight - 1))
        .contentShape(Rectangle())
        .onHover { hover.wrappedValue = $0 }
        .onTapGesture { if item.isClosable { close() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Close \(item.title)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHidden(!item.isClosable)
        .accessibilityAction { if item.isClosable { close() } }
        return VStack(spacing: Pixels(0)) {
            if let identifier = item.closeAccessibilityIdentifier { body.accessibilityIdentifier(identifier) } else { body }
        }
    }
}
