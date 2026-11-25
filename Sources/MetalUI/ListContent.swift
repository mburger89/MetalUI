import MetalUICore
import MetalUILayout

// The content form of `List` and its `.sidebar` row chrome (outline lane 4, rulings `OG-A`, `OG-B`, `OG-E`, `OG-J`; probe
// `docs/probes/swiftui-outline.swift` arms `P-L1`..`P-L4`, `P-K1`, `P-K7`, `P-C1`, `P-R1`).
//
// A content `List` is lane 2's lazy tree behind a `ListContentEngine`: the same `LazyStackEngine` a `LazyVStack` uses
// (spacing 0, leading, rows as wide as the list), with each realised unit wrapped in a row of the list's own chrome. The
// engine adds what the stack does not have: a selection (read once per frame, written only from input), the arrow keys
// over the visible units, the accessibility rows, and a row wrapper that registers the click target BEFORE the unit's own
// content does, so a control inside a row (the chevron) ranks above the row it sits in.

// MARK: placeholder types

/// One row of a content `List`'s placeholder collection, identified by its selection value. Never constructed: a content
/// list's rows are its `content`'s, not a collection's (class `M`).
public struct ListContentRow<SelectionValue: Hashable>: Identifiable {
    /// The row's selection value.
    public var id: SelectionValue
}

/// The `Data` parameter of a content `List` (`List(selection:content:)`, `List(content:)`, the outline `List` inits): an
/// empty collection that only names the selection type, `List<ListContentRows<SelectionValue>, ListContentBody<Content>>`
/// (class `M`; SwiftUI's `List<SelectionValue, Content>` has no collection parameter).
public struct ListContentRows<SelectionValue: Hashable>: RandomAccessCollection {
    /// Always 0: the collection is empty.
    public var startIndex: Int { 0 }
    /// Always 0: the collection is empty.
    public var endIndex: Int { 0 }
    /// Never reachable: the collection has no rows.
    public subscript(position: Int) -> ListContentRow<SelectionValue> {
        preconditionFailure("a content List has no data rows")
    }
}

/// The `Row` parameter of a content `List`: it names the content's type and builds nothing (class `M`).
public struct ListContentBody<Content: ProposalElementGroup>: Element {
    init() {}

    public func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.frame.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 0, height: 0)) }, ())
    }

    public func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                         pass: inout PrepaintPass) {}

    public func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
                      pass: inout PaintPass) {}
}

// MARK: selection value of a row

/// An element that carries a `.tag(_:)` (`TaggedElement`), so a content list can select by it (`OG-E`).
@MainActor
protocol ListRowTagged {
    var listRowTag: AnyHashable { get }
}

extension TaggedElement: ListRowTagged {
    var listRowTag: AnyHashable { tag }
}

// MARK: the `.sidebar` row chrome

/// The `.sidebar` look of a content list's rows (`OG-J`, probes `P-L1`..`P-L4`), and the flag that tells a disclosure
/// group building its label row that it is inside one.
@MainActor
enum ListRowChrome {
    /// A row is this high (`P-L1`: 32; the standalone group's is 24).
    static let rowHeight: Double = 32
    /// The first row sits this far below the list's top (`P-L1`).
    static let topInset: Double = 10
    /// Each level of depth indents by this much (`P-L1`).
    static let indentPerLevel: Double = 12
    /// The chevron cell's width, at x `12 + 12 * depth` (`P-L1`); the label starts at its trailing edge.
    static let chevronCell: Double = 13
    /// A leaf's label x at depth 0 in a list that has a hierarchy: it reserves the chevron slot (`P-L2`).
    static let hierarchicalLeading: Double = 25
    /// A row's label x in a list with no hierarchy (`P-L1`'s flat control).
    static let flatLeading: Double = 16
    /// The selection highlight's inset from the list's edge on each side, and its corner radius (`P-L4`).
    static let highlightInset: Double = 10
    static let highlightRadius: Double = 8

    /// Whether a content list is building its rows, so a `DisclosureGroup`'s label row takes the list's chrome.
    private(set) static var isActive = false

    static func whileActive<R>(_ body: () -> R) -> R {
        let outer = isActive
        isActive = true
        defer { isActive = outer }
        return body()
    }

    /// Where a row's content starts: a label row's chevron cell at `12 + 12 * depth`, any other row at
    /// `25 + 12 * depth` in a list with a hierarchy and 16 in a flat one.
    static func leading(depth: Int, isHeader: Bool, hierarchical: Bool) -> Double {
        if isHeader { return 12 + indentPerLevel * Double(depth) }
        return hierarchical ? hierarchicalLeading + indentPerLevel * Double(depth) : flatLeading
    }
}

extension DisclosureGroupBody {
    /// The label row inside a content `List` (`OG-J`, `P-L1`, `P-L3`): a 13 point chevron cell as tall as the row, then the
    /// label. Only the chevron cell toggles (`P-C1`); a click anywhere else on the row is the list's, and selects. The
    /// chevron is the secondary level (`P-L3` measured #808080 light, #7C7C7C dark: secondary is 0.498 of black over white,
    /// #808080), a glyph swap as the standalone group's is; it is not focusable (`FC-F`: the list is the one focus stop).
    /// A ⌥-click on the chevron runs `cascade` instead of the plain toggle (`P-C1`).
    func listHeader(cascade: (@MainActor (Bool) -> Void)?) -> some ElementGroup {
        let open = isExpanded
        let toggle = self.toggle
        return HStack(alignment: .center, spacing: Pixels(0)) {
            Image(systemName: open ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: Pixels(Float(ListRowChrome.chevronCell)), height: Pixels(Float(ListRowChrome.rowHeight)))
                .onClick {
                    // ⌥-click cascades like ⌥→ and ⌥← (`P-C1`). An `onClick`, not a tap gesture: only a click reads the
                    // modifiers of the mouse-up (`ClickDispatch`).
                    if let cascade, ClickDispatch.modifiers == .option { cascade(!open) } else { toggle() }
                }
                .accessibilityHidden(true)   // the row's triangle child is the client's way in (`OG-F`)
            label
            Spacer()
        }
    }
}

/// One row's chrome as a native layout over the unit's own nodes: the content starts `leading` points in, is at least
/// `minHeight` tall and centred in that, and the first row has `topInset` more above it (inside the unit's extent, so
/// the lazy index measures it).
struct ListRowChromeLayout: ProposalLayout {
    var leading: Double
    var minHeight: Double
    var topInset: Double

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let inner = ProposedSize(width: width.map { Swift.max(0, $0 - leading) }, height: nil)
        var content = 0.0, widest = 0.0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(inner).size
            content += size.height
            widest = Swift.max(widest, size.width)
        }
        return LayoutMeasurement(size: SizeD(width: width ?? leading + widest,
                                             height: Swift.max(minHeight, content) + topInset))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        let inner = ProposedSize(width: Swift.max(0, bounds.width - leading), height: nil)
        let sizes = subviews.indices.map { subviews[$0].sizeThatFits(inner).size }
        let content = sizes.reduce(0.0) { $0 + $1.height }
        var y = bounds.y + topInset + Swift.max(0, (bounds.height - topInset - content) / 2)
        for index in subviews.indices {
            subviews[index].place(at: Point(x: bounds.x + leading, y: y), anchor: .topLeading, proposal: inner)
            y += sizes[index].height
        }
    }
}

/// What a lazy stack tells its unit wrapper (`LazyStackEngine.unitWrapper`).
struct LazyUnitWrapContext {
    /// The container's units, so a wrapper can ask a unit's id and tag.
    let table: LazyUnitTable
    /// Whether the window came from a known viewport (a bounded plan), for the accessibility row index.
    let bounded: Bool
}

/// Where a row's chrome ended up in prepaint, for its paint (a reference, shared by the box's two closures).
@MainActor
private final class ListRowGeometry {
    var rect: Bounds<Pixels>?
}

// MARK: the engine

/// What `List` runs for its content form, type-erased over the content and selection types.
@MainActor
protocol ListContentRunning: AnyObject {
    /// The caller's handlers and decoration for the list (`.onKey`, `.background`, ...), set before each phase.
    var handlers: Handlers { get set }
    var decoration: Decoration { get set }
    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> LayoutNodeID
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, pass: inout PrepaintPass)
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, pass: inout PaintPass)
}

/// A content `List`'s engine: `LazyStackEngine` over the content, its units wrapped in `.sidebar` rows, with a selection
/// of `SelectionValue`s (`OG-E`, `OG-J`).
///
/// **A row's selection value** is its element's `.tag(_:)` when it has one that casts to `SelectionValue`, else the id
/// the unit is known by (`ForEach` element id, an outline row's element id) when that casts; a unit with neither (a
/// header, a spacer, a tag of another type) is a row that cannot be selected and the arrow keys step over it.
@MainActor
final class ListContentEngine<SelectionValue: Hashable, Content: ProposalElementGroup>: ListContentRunning {
    var handlers = Handlers()
    var decoration = Decoration()

    private var stack: LazyStackEngine<Content>
    private let selection: ListSelection<SelectionValue>
    /// Whether the content holds a disclosure or an outline, so a leaf's label reserves the chevron slot (`P-L2`).
    private let hierarchical: Bool
    private var state: LazyStackState<Content>?
    private var prepaintState: LazyStackPrepaint<Content>?
    private var bounded = false
    private var awaitsViewport = false
    /// The rows this frame realised, by their chrome id, for an accessibility selection.
    private var rowValues: [GlobalElementID: SelectionValue] = [:]
    /// The `contextMenu(forSelectionType:)` this list took in layout (`OG-N`), kept only when its identifier type is the
    /// list's selection type.
    private var menuSpec: SelectionContextMenu?

    init(content: Content, selection: ListSelection<SelectionValue>) {
        self.selection = selection
        hierarchical = lazyTreeCapableType(Content.self)
        stack = LazyStackEngine(content: content, spacing: Pixels(0), axis: .vertical,
                                alignment: HorizontalAlignment.leading.proposalAlignment)
        stack.cachesFlatten = true   // `OG-O`
        stack.animatesSplices = true   // `OG-P`
    }

    // MARK: ids

    /// The entry the lead and anchor live in: the lazy stack's origin is at the list's own id and the table keys by id alone.
    private static func leadID(_ list: GlobalElementID) -> GlobalElementID {
        GlobalElementID.child(of: list, at: 0, name: ElementID("$listlead"))
    }

    /// The entry a pending ⌥ cascade lives in (`OutlineCascade`): the groups whose descendants the next build expands or collapses.
    private static func cascadeID(_ list: GlobalElementID) -> GlobalElementID {
        GlobalElementID.child(of: list, at: 0, name: ElementID("$listcascade"))
    }

    /// A row's chrome id (its hitbox, its accessibility row), named by the unit's key under the list.
    private static func rowID(_ list: GlobalElementID, unitKey: AnyHashable) -> GlobalElementID {
        GlobalElementID.child(of: list, at: 0, name: ElementID(name: "row " + String(describing: unitKey.base), key: IdentityKey(unitKey)))
    }

    /// A unit's prepaint, under `backgroundProminence` `.increased` when the row is selected (`OG-Q`).
    private static func prepaint(_ box: LazyUnitBox, increased: Bool, _ pass: inout PrepaintPass) {
        if increased { let frame = pass.frame; frame.withIncreasedProminence { box.prepaint(&pass) } } else { box.prepaint(&pass) }
    }

    /// A unit's paint, under `backgroundProminence` `.increased` when the row is selected (`OG-Q`).
    private static func paint(_ box: LazyUnitBox, increased: Bool, _ pass: inout PaintPass) {
        if increased { let frame = pass.frame; frame.withIncreasedProminence { box.paint(&pass) } } else { box.paint(&pass) }
    }

    /// The value a unit selects by: its tag, else its id, whichever casts (`OG-E`).
    private static func value(of unit: Int, in table: LazyUnitTable) -> SelectionValue? {
        if let tag = table.selectionTag(unit)?.base as? SelectionValue { return tag }
        return table.rawID(unit).base as? SelectionValue
    }

    private func controller(table: LazyUnitTable, list: GlobalElementID,
                            stateTable: StateTable) -> ListSelectionController<SelectionValue> {
        let space = ListRowSpace<SelectionValue>(
            count: table.count,
            id: { Self.value(of: $0, in: table) },
            index: { value in
                for unit in 0..<table.count where Self.value(of: unit, in: table) == value { return unit }
                return nil
            })
        let leadID = Self.leadID(list)
        let leads = ListLeadStore(
            read: { [weak stateTable] in
                guard let stateTable else { return nil }
                let origin = stateTable.peek(leadID, as: ListOrigin.self) ?? ListOrigin()
                return (origin.lead, origin.anchor)
            },
            write: { [weak stateTable] lead, anchor in
                stateTable?.withState(leadID, initial: ListOrigin()) {
                    $0.lead = lead
                    $0.anchor = anchor
                }
            })
        return ListSelectionController(space: space, selection: selection, leads: leads, list: list)
    }

    // MARK: layout

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> LayoutNodeID {
        pass.frame.stateTable.mark(Self.leadID(id))
        let cascadeID = Self.cascadeID(id)
        pass.frame.stateTable.mark(cascadeID)
        let pendingCascades = pass.frame.stateTable.peek(cascadeID, as: [GlobalElementID: Bool].self) ?? [:]
        let lifecycle = pass.frame.animationStore.lifecycle
        let cascadeContext = OutlineCascade.Context(
            pending: pendingCascades,
            queue: { owner, write in lifecycle.enqueue(LifecycleEvent(owner: owner, action: { write() }, departed: nil)) },
            request: { [weak table = pass.frame.stateTable] group, expand in
                guard let table else { return }
                OutlineSplice.noteInput(group)   // `OG-P`: the ⌥ cascade's rows slide as a plain toggle's do
                var current = table.peek(cascadeID, as: [GlobalElementID: Bool].self) ?? [:]
                current[group] = expand
                table.write(cascadeID, current)
            })
        rowValues = [:]
        let menuSpec = (handlers.contextual?.selection ?? pass.frame.environmentTop.selectionContextMenu)
            .flatMap { $0.applies(to: SelectionValue.self) ? $0 : nil }
        self.menuSpec = menuSpec
        let reader = selection.reader()
        let highlight = pass.frame.environmentTop.tint ?? Color(.accent)
        let stateTable = pass.frame.stateTable
        var engine = stack
        // `OG-Q`: a selected unit builds, prepaints and paints with `.increased`. The unit's value is asked before it is
        // realised, so only a list with something selected asks, and only a tagged ForEach pays its closure a second call.
        if reader != nil, selection.hasSelectedValue {
            engine.unitIncreased = { [reader] table, unit in
                LazyPrebuild.storing = true
                defer { LazyPrebuild.storing = false }
                guard let value = Self.value(of: unit, in: table) else { return false }
                return reader?(value) ?? false
            }
        }
        var controllerOf: ListSelectionController<SelectionValue>?
        var values: [GlobalElementID: SelectionValue] = [:]
        engine.unitWrapper = { [hierarchical, selection] box, context, pass in
            guard !box.nodes.isEmpty else { return box }
            let leading = ListRowChrome.leading(depth: box.depth, isHeader: box.isDisclosureHeader,
                                                hierarchical: hierarchical)
            let topInset = box.unit == 0 ? ListRowChrome.topInset : 0
            let chrome = pass.requestNativeLayout(
                ListRowChromeLayout(leading: leading, minHeight: ListRowChrome.rowHeight, topInset: topInset),
                children: box.nodes)
            let rowID = Self.rowID(id, unitKey: context.table.key(box.unit))   // the table's key: a box's own may repeat
            // The value the row selects by: its tag first, else its id (a content list's own rule, `OG-E`).
            let value = (box.selectionTag?.base as? SelectionValue)
                ?? (context.table.rawID(box.unit).base as? SelectionValue)
            var rowHandlers: Handlers?
            var selected = false
            if !selection.isNone, let value {
                if controllerOf == nil { controllerOf = self.controller(table: context.table, list: id, stateTable: stateTable) }
                var handlers = Handlers()
                handlers.onClick = controllerOf?.rowClick(row: value)
                handlers.axNode.isSelectableRow = true
                if let reader, reader(value) {
                    selected = true
                    handlers.axNode.selectionHint = true
                }
                if context.bounded && pass.collectsAccessibility { handlers.axNode.logicalIndex = box.unit }
                rowHandlers = handlers
                values[rowID] = value
            }
            // `OG-N`: the row's menu and its double-click primary action.
            if let menuSpec, let value {
                var handlers = rowHandlers ?? Handlers()
                handlers.onClick = menuSpec.clickHandler(wrapping: handlers.onClick, row: value)
                handlers.contextual = menuSpec.rowAttachment(row: value) { selection.currentSet() }
                rowHandlers = handlers
            }
            // An outline row tells a client its level, whether it is a group and open, and (a group) can expand or collapse
            // (`OG-F`); a row of an outline with no selection is published too.
            if hierarchical, pass.collectsAccessibility {
                var handlers = rowHandlers ?? Handlers()
                if context.bounded, handlers.axNode.logicalIndex == nil { handlers.axNode.logicalIndex = box.unit }
                let disclosure = context.table.disclosure(box.unit)
                let state: AXOutlineHint.State = disclosure.map { $0.isExpanded() ? .expanded : .collapsed } ?? .leaf
                handlers.axNode.outlineHint = AXOutlineHint(level: box.depth, state: state)
                if let disclosure {
                    handlers.actions[ObjectIdentifier(AccessibilityDisclosure.self)] = { action in
                        guard let request = action as? AccessibilityDisclosure else { return }
                        disclosure.set(request.expand)
                    }
                }
                rowHandlers = handlers
            }
            let geometry = ListRowGeometry()
            var fill = Decoration()
            fill.background = highlight
            fill.cornerRadius = Pixels(Float(ListRowChrome.highlightRadius))
            let wrapped = LazyUnitBox(
                unit: box.unit, key: box.key, nodes: [chrome],
                prepaint: { pass in
                    let all = pass.bounds(of: chrome.layoutNodeID)
                    let row = Bounds(origin: Point(x: all.origin.x, y: all.origin.y + Pixels(Float(topInset))),
                                     size: Size(width: all.size.width,
                                                height: all.size.height - Pixels(Float(topInset))))
                    geometry.rect = row
                    if let rowHandlers {
                        // The row adopts the records its content makes (`OG-F`): its text is the row's child.
                        pass.registerAndScope(rowHandlers, Decoration(), at: row, for: rowID) {
                            pass.frame.withAccessibilityAdopter(rowID) { Self.prepaint(box, increased: selected, &pass) }
                        }
                    } else {
                        Self.prepaint(box, increased: selected, &pass)
                    }
                },
                paint: { pass in
                    guard selected, let row = geometry.rect else { return Self.paint(box, increased: selected, &pass) }
                    let inset = Pixels(Float(ListRowChrome.highlightInset))
                    let highlight = Bounds(origin: Point(x: row.origin.x + inset, y: row.origin.y),
                                           size: Size(width: row.size.width - inset - inset, height: row.size.height))
                    pass.paintDecoration(fill, in: highlight, for: rowID) { Self.paint(box, increased: true, &pass) }
                })
            wrapped.depth = box.depth
            wrapped.isDisclosureHeader = box.isDisclosureHeader
            wrapped.selectionTag = box.selectionTag
            return wrapped
        }
        let (node, laidOut) = ListRowChrome.whileActive {
            OutlineCascade.whileActive(cascadeContext) { engine.requestLayout(id, pass: &pass) }
        }
        // The requests this build carried out are spent once the window has run the writes they queued, in the same drain.
        if !pendingCascades.isEmpty {
            lifecycle.enqueue(LifecycleEvent(owner: id, action: { [weak table = pass.frame.stateTable] in
                table?.write(cascadeID, [GlobalElementID: Bool]())
            }, departed: nil))
        }
        engine.unitWrapper = nil
        engine.unitIncreased = nil
        stack = engine
        state = laidOut
        rowValues = values
        bounded = laidOut.plan?.mode == .bounded
        awaitsViewport = laidOut.plan?.mode == .cold
        return node.layoutNodeID
    }

    // MARK: prepaint and paint

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, pass: inout PrepaintPass) {
        guard var laidOut = state else { return }
        var listHandlers = handlers
        if listHandlers.axNode.isEmpty { listHandlers.axNode = AXNode(role: .container) }
        if hierarchical { listHandlers.axNode.outlineHint = AXOutlineHint(level: 0, state: .list) }   // `OG-F`: a tree
        if let menuSpec { listHandlers.contextual = menuSpec.listAttachment(over: handlers.contextual) }   // `OG-N`
        if let table = laidOut.table {
            listHandlers.axNode.logicalCount = table.count
            if !selection.isNone { compose(&listHandlers, table: table, id: id, pass: pass) }
        }
        let frame = pass.frame
        let unbounded = pass.collectsAccessibility && !bounded
        if unbounded && awaitsViewport { frame.requestAccessibilityRetry() }
        // The first-draw seat (`FC-F`): the list holds the first responder itself, its rows are not candidates.
        var held: LazyStackPrepaint<Content>?
        var engine = stack
        frame.insideListRows {
            // An unbounded window publishes the table and no rows (`AB-X` rule 1), as the data list does.
            if unbounded {
                frame.withAccessibilitySuppressed(except: id) {
                    held = registerAndPrepaint(id, bounds: bounds, handlers: listHandlers, engine: &engine,
                                               layout: &laidOut, pass: &pass)
                }
            } else {
                held = registerAndPrepaint(id, bounds: bounds, handlers: listHandlers, engine: &engine,
                                           layout: &laidOut, pass: &pass)
            }
        }
        stack = engine
        state = laidOut
        prepaintState = held
    }

    private func registerAndPrepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, handlers: Handlers,
                                     engine: inout LazyStackEngine<Content>, layout: inout LazyStackState<Content>,
                                     pass: inout PrepaintPass) -> LazyStackPrepaint<Content> {
        var result: LazyStackPrepaint<Content>?
        var inner = engine
        var state = layout
        pass.registerAndScope(handlers, Decoration(), at: bounds, for: id) {
            result = inner.prepaint(id, bounds: bounds, layout: &state, pass: &pass)
        }
        engine = inner
        layout = state
        return scopeResult(result)
    }

    /// The list's focus, its arrow keys over the visible units and its accessibility selection (`DD-T`, `DD-Z` item 6,
    /// `OG-E`). The caller's own `onKey` runs first.
    private func compose(_ listHandlers: inout Handlers, table: LazyUnitTable, id: GlobalElementID, pass: PrepaintPass) {
        let stateTable = pass.frame.stateTable
        let queue = pass.frame.scrollRequestQueue
        let controller = self.controller(table: table, list: id, stateTable: stateTable)
        let callerKey = handlers.onKey
        listHandlers.isFocusable = true
        let hierarchical = self.hierarchical
        let menuSpec = self.menuSpec
        let selection = self.selection
        listHandlers.onKey = { [weak queue] event in
            if let callerKey, callerKey(event) { return true }
            // Return runs the primary action on the selection (`OG-N`, `P-M4`).
            if let menuSpec, menuSpec.returnKey(event, selection: Set(selection.currentSet().map { AnyHashable($0) })) {
                return true
            }
            // The new lead is revealed like any `scrollTo` of its id (`OG-E`: the key moves reveal the lead).
            @MainActor func reveal(_ index: Int) {
                if let scope = id.parent {
                    queue?.enqueue(ScrollRequest(scope: scope, key: table.rawID(index), anchor: nil))
                }
            }
            if let move = ControlKeys.listMove(event) {
                guard let moved = controller.move(move.direction, extends: move.extends) else { return false }
                reveal(moved.index)
                return true
            }
            guard hierarchical, let key = ControlKeys.outlineDisclosure(event) else { return false }
            if let parent = Self.disclose(key, table: table, controller: controller) { reveal(parent) }
            return true
        }
        let rows = rowValues
        listHandlers.actions[ObjectIdentifier(AccessibilityRowSelection.self)] =
            controller.accessibilityRowSelection { rows }
    }

    /// An outline list's ← and → (`OG-E`, probes `P-K2`..`P-K5`), on the lead row: → expands a collapsed group, ← collapses
    /// an expanded one or selects the parent of a leaf or a collapsed group; with ⌥ they cascade. Anything else does
    /// nothing, and the selection never changes but by moving to a parent. Returns the position to reveal, if the
    /// selection moved. The key is consumed whenever the list has a lead row.
    @inline(never)
    private static func disclose(_ key: (direction: ControlKeys.Direction, cascades: Bool), table: LazyUnitTable,
                                 controller: ListSelectionController<SelectionValue>) -> Int? {
        guard let lead = controller.leadPosition() else { return nil }
        let disclosure = table.disclosure(lead)
        switch key.direction {
        case .forward:
            guard let disclosure, !disclosure.isExpanded() else { return nil }
            if key.cascades { disclosure.cascade(true) } else { disclosure.set(true) }
            return nil
        case .backward:
            if let disclosure, disclosure.isExpanded() {
                if key.cascades { disclosure.cascade(false) } else { disclosure.set(false) }
                return nil
            }
            // A leaf or a collapsed group: the parent is the nearest row above at a lower level.
            let depth = table.depth(lead)
            guard depth > 0 else { return nil }
            var position = lead - 1
            while position >= 0, table.depth(position) >= depth { position -= 1 }
            guard position >= 0, controller.select(position: position) != nil else { return nil }
            return position
        }
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, pass: inout PaintPass) {
        guard var laidOut = state, var held = prepaintState else { return }
        var engine = stack
        pass.paintDecoration(decoration, in: bounds, for: id) {
            engine.paint(id, bounds: bounds, layout: &laidOut, prepaint: &held, pass: &pass)
        }
        stack = engine
        state = laidOut
        prepaintState = held
    }
}

// MARK: the content inits (SwiftUI's `List(selection:content:)`)

extension List {
    /// A list of `content` whose rows select into the set `selection` (SwiftUI's `List(selection:content:)`, ruling
    /// `OG-A`): the hierarchical form, the rows being whatever `content` makes, a `ForEach`, a `DisclosureGroup`, an
    /// `OutlineGroup`. Needs an enclosing vertical `ScrollView` (divergence 84, amended). A row's value is its `.tag(_:)`,
    /// else its `ForEach` element's id when that casts to `SelectionValue`.
    public init<SelectionValue: Hashable, Content: ProposalElementGroup>(
        selection: Binding<Set<SelectionValue>>?, @ProposalContentBuilder content: () -> Content
    ) where Data == ListContentRows<SelectionValue>, Row == ListContentBody<Content> {
        self.init(content: content(), selection: selection.map { .multi($0) } ?? .none)
    }

    /// A list of `content` whose rows select into `selection`, one row at a time (SwiftUI's
    /// `List(selection:content:)` over an optional value). The binding keeps a value no visible row carries (a row inside a
    /// collapsed group), writes nothing for it, and shows no row selected (`P-K7`).
    public init<SelectionValue: Hashable, Content: ProposalElementGroup>(
        selection: Binding<SelectionValue?>?, @ProposalContentBuilder content: () -> Content
    ) where Data == ListContentRows<SelectionValue>, Row == ListContentBody<Content> {
        self.init(content: content(), selection: selection.map { .single($0) } ?? .none)
    }

    /// A list of `content` over a non-optional selection (SwiftUI's disfavoured `List(selection:content:)`): a row's click
    /// writes its value; nothing writes `nil`.
    @_disfavoredOverload
    public init<SelectionValue: Hashable, Content: ProposalElementGroup>(
        selection: Binding<SelectionValue>, @ProposalContentBuilder content: () -> Content
    ) where Data == ListContentRows<SelectionValue>, Row == ListContentBody<Content> {
        let optional = Binding<SelectionValue?>(get: { selection.wrappedValue },
                                                set: { if let value = $0 { selection.wrappedValue = value } })
        self.init(content: content(), selection: .single(optional))
    }

    /// A list of `content` with no selection (SwiftUI's `List(content:)`, `SelectionValue == Never`): rows lay out and
    /// scroll, nothing selects, the arrow keys do nothing.
    public init<Content: ProposalElementGroup>(
        @ProposalContentBuilder content: () -> Content
    ) where Data == ListContentRows<Never>, Row == ListContentBody<Content> {
        self.init(content: content(), selection: .none)
    }
}

// MARK: the outline inits (SwiftUI's `List(_:children:rowContent:)`)

/// What `List(_:children:...)` makes of its data: `List(selection:) { OutlineGroup(...) }`, whose content the builder
/// adopts as `LegacyContent` (an `OutlineGroup` is an `ElementGroup`, not a proposal one).
public typealias ListOutlineBody<D: RandomAccessCollection, ID: Hashable, RowContent: ElementGroup>
    = ListContentBody<LegacyContent<OutlineGroup<D, ID, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>>>>

extension List {
    /// An outline of `data` whose rows select into the set `selection` (SwiftUI's `List(_:children:selection:rowContent:)`,
    /// ruling `OG-A`): literally `List(selection:) { OutlineGroup(data, children: children, content: rowContent) }`.
    public init<D: RandomAccessCollection, SelectionValue: Hashable, RowContent: ElementGroup>(
        _ data: D, children: KeyPath<D.Element, D?>, selection: Binding<Set<SelectionValue>>?,
        @ElementBuilder rowContent: @escaping (D.Element) -> RowContent
    ) where D.Element: Identifiable, Data == ListContentRows<SelectionValue>,
            Row == ListOutlineBody<D, D.Element.ID, RowContent> {
        self.init(selection: selection) { OutlineGroup(data, children: children, content: rowContent) }
    }

    /// An outline of `data` whose rows select into `selection`, one at a time (the optional form).
    public init<D: RandomAccessCollection, SelectionValue: Hashable, RowContent: ElementGroup>(
        _ data: D, children: KeyPath<D.Element, D?>, selection: Binding<SelectionValue?>?,
        @ElementBuilder rowContent: @escaping (D.Element) -> RowContent
    ) where D.Element: Identifiable, Data == ListContentRows<SelectionValue>,
            Row == ListOutlineBody<D, D.Element.ID, RowContent> {
        self.init(selection: selection) { OutlineGroup(data, children: children, content: rowContent) }
    }

    /// An outline of `data` over a non-optional selection (disfavoured, as SwiftUI's).
    @_disfavoredOverload
    public init<D: RandomAccessCollection, SelectionValue: Hashable, RowContent: ElementGroup>(
        _ data: D, children: KeyPath<D.Element, D?>, selection: Binding<SelectionValue>,
        @ElementBuilder rowContent: @escaping (D.Element) -> RowContent
    ) where D.Element: Identifiable, Data == ListContentRows<SelectionValue>,
            Row == ListOutlineBody<D, D.Element.ID, RowContent> {
        self.init(selection: selection) { OutlineGroup(data, children: children, content: rowContent) }
    }

    /// An outline of `data` with no selection (SwiftUI's `List(_:children:rowContent:)`).
    public init<D: RandomAccessCollection, RowContent: ElementGroup>(
        _ data: D, children: KeyPath<D.Element, D?>,
        @ElementBuilder rowContent: @escaping (D.Element) -> RowContent
    ) where D.Element: Identifiable, Data == ListContentRows<Never>,
            Row == ListOutlineBody<D, D.Element.ID, RowContent> {
        self.init { OutlineGroup(data, children: children, content: rowContent) }
    }

    /// An outline of `data` identified by `id`, selecting into the set `selection`
    /// (SwiftUI's `List(_:id:children:selection:rowContent:)`).
    public init<D: RandomAccessCollection, ID: Hashable, SelectionValue: Hashable, RowContent: ElementGroup>(
        _ data: D, id: KeyPath<D.Element, ID>, children: KeyPath<D.Element, D?>,
        selection: Binding<Set<SelectionValue>>?, @ElementBuilder rowContent: @escaping (D.Element) -> RowContent
    ) where Data == ListContentRows<SelectionValue>, Row == ListOutlineBody<D, ID, RowContent> {
        self.init(selection: selection) { OutlineGroup(data, id: id, children: children, content: rowContent) }
    }

    /// An outline of `data` identified by `id`, selecting into `selection` one row at a time.
    public init<D: RandomAccessCollection, ID: Hashable, SelectionValue: Hashable, RowContent: ElementGroup>(
        _ data: D, id: KeyPath<D.Element, ID>, children: KeyPath<D.Element, D?>,
        selection: Binding<SelectionValue?>?, @ElementBuilder rowContent: @escaping (D.Element) -> RowContent
    ) where Data == ListContentRows<SelectionValue>, Row == ListOutlineBody<D, ID, RowContent> {
        self.init(selection: selection) { OutlineGroup(data, id: id, children: children, content: rowContent) }
    }

    /// An outline of `data` identified by `id` over a non-optional selection (disfavoured).
    @_disfavoredOverload
    public init<D: RandomAccessCollection, ID: Hashable, SelectionValue: Hashable, RowContent: ElementGroup>(
        _ data: D, id: KeyPath<D.Element, ID>, children: KeyPath<D.Element, D?>,
        selection: Binding<SelectionValue>, @ElementBuilder rowContent: @escaping (D.Element) -> RowContent
    ) where Data == ListContentRows<SelectionValue>, Row == ListOutlineBody<D, ID, RowContent> {
        self.init(selection: selection) { OutlineGroup(data, id: id, children: children, content: rowContent) }
    }

    /// An outline of `data` identified by `id` with no selection.
    public init<D: RandomAccessCollection, ID: Hashable, RowContent: ElementGroup>(
        _ data: D, id: KeyPath<D.Element, ID>, children: KeyPath<D.Element, D?>,
        @ElementBuilder rowContent: @escaping (D.Element) -> RowContent
    ) where Data == ListContentRows<Never>, Row == ListOutlineBody<D, ID, RowContent> {
        self.init { OutlineGroup(data, id: id, children: children, content: rowContent) }
    }
}
