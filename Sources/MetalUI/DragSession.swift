import MetalUICore
import MetalUIPlatform

// Drag and drop's session, target resolution and import (rulings `DN-C`,
// `DN-F`, `DN-H`, `DN-I`, `DN-K`). One resolver and one importer serve both an
// in-window drag and a drag from outside the window. The preview is lane 2's
// (`DN-J`, `DN-T`).

/// An in-window drag (ruling `DN-H`): opened when a draggable wins its arena,
/// ended by a release, Escape, or the platform taking it at the window's edge.
struct DragSession {
    /// The source element's id.
    let sourceID: GlobalElementID
    /// The payload, exported once when the drag began (`DN-H` item 4).
    let representations: [DragRepresentation]
    /// Where the press that began the drag landed, in window points.
    let pressPoint: Point<Pixels>
    /// The pointer, in window points.
    var pointer: Point<Pixels>
    /// Whether the drag has been offered to the platform (`DN-K`): once per
    /// session, at the first move outside the window.
    var offeredExternally = false

    /// The payload as the one item a destination imports from (`DN-H` item
    /// 2), its `load` answering from the exported bytes.
    var items: [DropItem] {
        let representations = self.representations
        return [DropItem(types: representations.map(\.type)) { identifier in
            representations.first { $0.type.identifier == identifier }?.bytes
        }]
    }
}

/// The destination a drag is over (`DN-H` item 1): its id, its destination
/// record from the last drawn frame, and its origin for the action's local
/// location (`DN-H` item 2).
struct DropTargetState {
    let id: GlobalElementID
    let target: DropDestinationTarget
    let origin: Point<Pixels>
}

extension Window {
    // MARK: The in-window session

    /// Opens a session for a draggable that won its arena (`DN-D` item 7),
    /// exporting its payload now, once (`DN-H`).
    func beginDragSession(from source: GlobalElementID, source payload: DragSource,
                          pressedAt press: Point<Pixels>) {
        endPressForDrag()
        let pointer = lastMousePosition ?? press
        dragSession = DragSession(sourceID: source, representations: payload.export(),
                                  pressPoint: press, pointer: pointer)
        retarget(at: pointer, items: dragSession?.items)
        setNeedsRedraw()
    }

    /// An open session's turn at an input event, first after the pointer
    /// bookkeeping (`Window.onInput`); whether it claimed the event.
    func dispatchDragSession(_ event: InputEvent) -> Bool {
        guard var session = dragSession else { return false }
        switch event {
        case .mouseDragged(let mouse):
            session.pointer = mouse.position
            if !session.offeredExternally && !contentBounds.contains(mouse.position) {
                // The window's edge (`DN-K` item 1): offered once; a platform
                // that takes it owns the drag from here, and its session
                // swallows the release, so ours ends silently now.
                session.offeredExternally = true
                dragSession = session
                if offerExternalDrag(session.representations, at: mouse.position) {
                    endDragSession()
                    return true
                }
            }
            dragSession = session
            retarget(at: mouse.position, items: session.items)
            return true
        case .mouseUp(let mouse):
            // Never a click (`DN-D` item 7): a release over an accepting
            // destination drops, anywhere else cancels (`DN-I`).
            retarget(at: mouse.position, items: session.items)
            _ = deliver(session.items, at: mouse.position)
            endDragSession()
            return true
        case .keyDown(let key) where key.charactersIgnoringModifiers == "\u{1b}":
            // Escape cancels, ahead of the keymap (`DN-I`, `P7`).
            endDragSession()
            return true
        default:
            return false
        }
    }

    /// Ends the session: the target turns `false`, nothing is delivered
    /// (`DN-I`), and the press's bookkeeping is cleared (`DN-K` item 1).
    func endDragSession() {
        untarget()
        dragSession = nil
        endPressForDrag()
        setNeedsRedraw()
    }

    // MARK: Drops from outside the window

    /// A drag from outside the window (`DN-C` item 1): `.entered`/`.moved`
    /// answer whether an accepting destination is under the pointer,
    /// `.performed` whether a destination took the drop (`true` whatever its
    /// action returned, `R4`).
    func dispatchExternalDrop(_ event: DropEvent) -> Bool {
        switch event {
        case .entered(let position, let items):
            externalDropItems = .some(items)
            retarget(at: position, items: items)
            return dropTarget != nil
        case .moved(let position):
            let items = externalDropItems ?? nil
            retarget(at: position, items: items)
            return dropTarget != nil
        case .exited:
            externalDropItems = nil
            untarget()
            return false
        case .performed(let position, let items):
            externalDropItems = nil
            retarget(at: position, items: items)
            return deliver(items, at: position)
        }
    }

    // MARK: The one resolver and the one importer

    /// The window's content, in window points — what "leaving the window" means.
    private var contentBounds: Bounds<Pixels> {
        Bounds(origin: Point(x: Pixels(0), y: Pixels(0)), size: contentSizeForDrag)
    }

    /// The destination a drag of `items` at `point` targets (`DN-F`): the
    /// topmost destination region by the one ranking; none when the topmost
    /// opaque hitbox sits on a higher layer — a presentation above it
    /// (`DN-F` item 4) — or when it refuses the items (`DN-F` item 2: a
    /// refusing deepest destination does not pass the drop outward). Unknown
    /// items (`nil`, SDL) are accepted optimistically (`DN-M` item 2).
    func dropTarget(at point: Point<Pixels>, items: [DropItem]?) -> DropTargetState? {
        // The destination's own region, never the opaque hitbox of the same
        // element (which carries its whole `Handlers` and sits inside the
        // `allowsHitTesting` gate and its content shape).
        guard let index = topmostHitbox(in: lastHitboxes, at: point,
                                        where: { !$0.opaque && $0.handlers.dropDestination != nil }),
              let destination = lastHitboxes[index].handlers.dropDestination else { return nil }
        let region = lastHitboxes[index]
        if let cover = topmostOpaqueHitbox(in: lastHitboxes, at: point), lastHitboxes[cover].layer > region.layer {
            return nil
        }
        guard destination.accepts(items) else { return nil }
        return DropTargetState(id: region.id, target: destination, origin: region.origin)
    }

    /// Moves the target to whatever `dropTarget(at:items:)` answers, the old
    /// one's `false` strictly before the new one's `true` (`DN-H` item 1,
    /// `P14`); the same destination again sends nothing (`P19`).
    func retarget(at point: Point<Pixels>, items: [DropItem]?) {
        let new = dropTarget(at: point, items: items)
        if let current = dropTarget, let new, current.id == new.id {
            dropTarget = new   // this frame's record; no callback
            return
        }
        untarget()
        dropTarget = new
        if let new {
            StateDispatch.dispatching(to: new.id) { new.target.setTargeted(true) }
        }
    }

    /// Un-targets the current destination, if any, with its `false`.
    func untarget() {
        guard let current = dropTarget else { return }
        dropTarget = nil
        StateDispatch.dispatching(to: current.id) { current.target.setTargeted(false) }
    }

    /// Drops `items` on the current target at `point`: its `isTargeted(false)`
    /// first, then the import and the action at the destination-local point
    /// (`DN-H` items 1–3). Whether the action ran; `false` with no target.
    func deliver(_ items: [DropItem], at point: Point<Pixels>) -> Bool {
        guard let target = dropTarget else { return false }
        untarget()
        let location = Point(x: Pixels(point.x.value - target.origin.x.value),
                             y: Pixels(point.y.value - target.origin.y.value))
        return StateDispatch.dispatching(to: target.id) { target.target.deliver(items, at: location) }
    }
}
