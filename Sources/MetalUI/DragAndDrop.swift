import Foundation
import MetalUICore
import MetalUILayout
import MetalUIPlatform

// Drag and drop's public surface (rulings `DN-A`, `DN-P`): `draggable(_:)` and
// `dropDestination(for:action:isTargeted:)` on every `StyledElement` (returning
// `Self`, so no id moves) and on every `ProposalElementGroup` (one wrapper, one
// identity level — `GestureModifier`'s recipe). `draggable(_:preview:)` is lane
// 2's (`DN-T`). Evidence: `docs/probes/swiftui-drag-and-drop.swift`.
//
// **Not offered** (`DN-A` item 2, owner none): `.onDrag`/`.onDrop` and
// `DropDelegate` (their payload is `NSItemProvider`, an Apple-only type), and
// the `DropSession` family.

// MARK: - The two records `Handlers` carries

/// A draggable's payload, exported when the drag begins (ruling `DN-H`): the
/// `@autoclosure` runs then and only then, as SwiftUI's does.
final class DragSource {
    private let payload: () -> [DragRepresentation]

    init<T: Transferable>(_ payload: @escaping () -> T) {
        self.payload = { payload().dragRepresentations() }
    }

    /// The payload, exported as each of its types.
    @MainActor
    func export() -> [DragRepresentation] { payload() }
}

/// A drop destination (ruling `DN-F`): the types it imports, its importer
/// and action, and its `isTargeted` callback. One reference on `Handlers`
/// (`DN-P`, `IX-N`'s Windows stack budget).
final class DropDestinationTarget {
    /// `T.importedContentTypes()`, in declared order.
    let importedTypes: [ContentType]
    private let action: @MainActor ([DropItem], Point<Pixels>) -> Bool
    private let targeted: @MainActor (Bool) -> Void

    init<T: Transferable>(_ type: T.Type,
                          action: @escaping @MainActor ([T], Point<Pixels>) -> Bool,
                          isTargeted: @escaping @MainActor (Bool) -> Void) {
        let imported = T.importedContentTypes()
        self.importedTypes = imported
        self.targeted = isTargeted
        self.action = { items, location in
            let values: [T] = items.compactMap { item in
                guard let (offered, told) = Self.match(item, imported) else { return nil }
                guard let bytes = item.load(offered.identifier) else { return nil }
                // The destination's type, never the offered one (`DN-S` item 2).
                return T(importing: Data(bytes), contentType: told)
            }
            guard !values.isEmpty else { return false }
            _ = action(values, location)
            return true
        }
    }

    /// Whether `items` hold something this destination imports — `true` when
    /// the items are not known yet (SDL hovering, ruling `DN-M` item 2).
    func accepts(_ items: [DropItem]?) -> Bool {
        guard let items else { return true }
        return items.contains { Self.match($0, importedTypes) != nil }
    }

    /// Imports `items` and runs the action at `location`; whether it ran — so
    /// `true` whatever the action returned (`R4`, `DN-H` item 3), `false` when
    /// no item imported.
    @MainActor
    func deliver(_ items: [DropItem], at location: Point<Pixels>) -> Bool { action(items, location) }

    @MainActor
    func setTargeted(_ targeted: Bool) { self.targeted(targeted) }

    /// The item's first offered type that satisfies an imported one, and the
    /// imported type it satisfies: an exact match first, else the first of
    /// `imported`, in declared order, that it conforms to (`DN-S` item 2).
    static func match(_ item: DropItem, _ imported: [ContentType]) -> (PasteboardType, ContentType)? {
        for offered in item.types {
            if let exact = imported.first(where: { $0.identifier == offered.identifier }) {
                return (offered, exact)
            }
            if let parent = imported.first(where: { offered.satisfies($0.identifier) }) {
                return (offered, parent)
            }
        }
        return nil
    }
}

extension GestureAttachment {
    /// A draggable, as a gesture-arena member at normal priority (ruling `DN-D`).
    init(draggable source: DragSource) {
        var leaf = GestureLeaf(kind: .draggable)
        leaf.dragSource = source
        self.init(node: .leaf(leaf), priority: .normal)
    }

    /// Whether this attachment is a draggable (ruling `DN-E` item 1: it adds
    /// no opaque hit target).
    var isDraggable: Bool {
        if case .leaf(let leaf) = node, case .draggable = leaf.kind { return true }
        return false
    }
}

// MARK: - `StyledElement`

extension StyledElement {
    /// Makes this element a drag source carrying `payload` — SwiftUI's
    /// `draggable(_:)` (ruling `DN-A`).
    ///
    /// The drag begins on the first pointer move of more than zero points from
    /// a press on the element (`DN-D` item 1); it outranks a tap, a long press
    /// still undecided and a click (`DN-D` item 2), and yields to a
    /// `DragGesture` that outranks it (`DN-D` item 3). `payload` runs once,
    /// when the drag begins. A draggable adds **no opaque hit target** (`DN-E`):
    /// a click, hover or wheel that reached what lies under it still does.
    /// A disabled source does not drag — divergence 100 (`DN-G`).
    ///
    /// Appends to `Handlers.gestures` and returns `Self`, so no id moves (`DN-P`).
    public func draggable<T: Transferable>(_ payload: @autoclosure @escaping () -> T) -> Self {
        _ = DragSource(payload)
        return self   // RED-FIRST STUB
    }

    /// Makes this element a drop destination for `T` — SwiftUI's
    /// `dropDestination(for:action:isTargeted:)` (ruling `DN-A`), with the
    /// location in `Point<Pixels>`, local to this element (`DN-H` item 2).
    ///
    /// The destination under the pointer is the topmost one by the one hit
    /// ranking; a view covering it does not block it, a presentation above it
    /// does, and a deepest destination that refuses the payload's types
    /// targets nothing (`DN-F`). `isTargeted(false)` always precedes the next
    /// `true` and the action (`DN-H` item 1). The action receives every item
    /// that imports; if none does it does not run. `allowsHitTesting(false)`
    /// does not gate a destination; `hidden()` and `.disabled` do — the
    /// second is divergence 100 (`DN-G`).
    ///
    /// Sets `Handlers.dropDestination` — a later write replaces an earlier,
    /// `onClick`'s one-field rule (`R6e`) — and returns `Self` (`DN-P`).
    public func dropDestination<T: Transferable>(
        for payloadType: T.Type = T.self,
        action: @escaping @MainActor (_ items: [T], _ location: Point<Pixels>) -> Bool,
        isTargeted: @escaping @MainActor (Bool) -> Void = { _ in }) -> Self {
        _ = DropDestinationTarget(T.self, action: action, isTargeted: isTargeted)
        return self   // RED-FIRST STUB
    }
}

// MARK: - The proposal path

/// A proposal wrapper that makes its content a drag source — `GestureModifier`'s
/// recipe (ruling `DN-P`): no layout node, its one child numbered from 0 under
/// its id, one identity level.
public struct DraggableModifier<Content: ProposalElementGroup>: Element {
    /// The wrapped proposal content.
    public var content: Content
    var attachment: GestureAttachment

    init(content: Content, attachment: GestureAttachment) {
        self.content = content
        self.attachment = attachment
    }

    public struct Layout { var content: Content.GroupLayout }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        precondition(children.count == 1, "a draggable modifier requires one native child")
        return (children[0], Layout(content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        let handlers = Handlers()
        _ = attachment   // RED-FIRST STUB: registers nothing
        if false { pass.registerHandlers(handlers, at: bounds, id: id, accessibleText: nil,
                              synthesizesAccessibility: false) }
        return content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

extension DraggableModifier: ProposalElement {}

/// A proposal wrapper that makes its content a drop destination —
/// `GestureModifier`'s recipe (ruling `DN-P`).
public struct DropDestinationModifier<Content: ProposalElementGroup>: Element {
    /// The wrapped proposal content.
    public var content: Content
    var target: DropDestinationTarget

    init(content: Content, target: DropDestinationTarget) {
        self.content = content
        self.target = target
    }

    public struct Layout { var content: Content.GroupLayout }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        precondition(children.count == 1, "a drop destination modifier requires one native child")
        return (children[0], Layout(content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        let handlers = Handlers()
        _ = target   // RED-FIRST STUB: registers nothing
        if false { pass.registerHandlers(handlers, at: bounds, id: id, accessibleText: nil,
                              synthesizesAccessibility: false) }
        return content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

extension DropDestinationModifier: ProposalElement {}

extension ProposalElementGroup {
    /// `StyledElement.draggable(_:)` on the proposal path: wraps once (`DN-P`).
    public func draggable<T: Transferable>(_ payload: @autoclosure @escaping () -> T) -> DraggableModifier<Self> {
        let source = DragSource(payload)
        return DraggableModifier(content: self, attachment: GestureAttachment(draggable: source))
    }

    /// `StyledElement.dropDestination(for:action:isTargeted:)` on the
    /// proposal path: wraps once (`DN-P`).
    public func dropDestination<T: Transferable>(
        for payloadType: T.Type = T.self,
        action: @escaping @MainActor (_ items: [T], _ location: Point<Pixels>) -> Bool,
        isTargeted: @escaping @MainActor (Bool) -> Void = { _ in }) -> DropDestinationModifier<Self> {
        let target = DropDestinationTarget(T.self, action: action, isTargeted: isTargeted)
        return DropDestinationModifier(content: self, target: target)
    }
}
