import MetalUICore
import MetalUIPlatform
import MetalUIPrimitives

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
    /// The source's last painted primitives, before any effect (`DN-J`): kept
    /// when the source stops painting (`DN-H` item 4).
    var snapshot: [CapturedPrimitive] = []
    /// The source's origin when the drag began, in window points: the press
    /// point's offset into it stays under the pointer (`DN-J` items 2–3).
    var sourceOrigin: Point<Pixels>

    /// Where a custom preview's top-left goes: the pointer less the press
    /// point's offset into the source.
    var previewOrigin: Point<Pixels> {
        Point(x: Pixels(pointer.x.value - (pressPoint.x.value - sourceOrigin.x.value)),
              y: Pixels(pointer.y.value - (pressPoint.y.value - sourceOrigin.y.value)))
    }

    /// `pointer − pressPoint`: how far the snapshot is replayed from the source.
    var translation: Point<Pixels> {
        Point(x: Pixels(pointer.x.value - pressPoint.x.value), y: Pixels(pointer.y.value - pressPoint.y.value))
    }

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
    /// The destination region, whose stored inverse maps a window point into
    /// the space `origin` is in (`GX-P` item 3).
    var region: Hitbox? = nil
}

extension Window {
    // MARK: The in-window session

    /// Opens a session for a draggable that won its arena (`DN-D` item 7),
    /// exporting its payload now, once (`DN-H`).
    func beginDragSession(from source: GlobalElementID, source payload: DragSource,
                          pressedAt press: Point<Pixels>) {
        endPressForDrag()
        let pointer = lastMousePosition ?? press
        let origin = lastHitboxes.last { $0.id == source }?.origin ?? press
        dragSession = DragSession(sourceID: source, representations: payload.export(),
                                  pressPoint: press, pointer: pointer, sourceOrigin: origin)
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
            setNeedsRedraw()   // the preview follows the pointer (`DN-J`)
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
        return DropTargetState(id: region.id, target: destination, origin: region.origin, region: region)
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
        let point = target.region?.localPoint(point) ?? point
        let location = Point(x: Pixels(point.x.value - target.origin.x.value),
                             y: Pixels(point.y.value - target.origin.y.value))
        return StateDispatch.dispatching(to: target.id) { target.target.deliver(items, at: location) }
    }
}

extension PaintPass {
    /// Runs `body`, capturing what it emits as the drag preview's snapshot
    /// when `id` is the open session's source (`DN-J` item 1): an identity
    /// capture `PaintScope`, so the scene receives exactly what it would
    /// have, and a source inside a `.transition` group is captured before the
    /// transition's effect (`DN-U` item 6). A frame without a session never
    /// pushes one. Called by `paintDecoration` — every `StyledElement` site —
    /// and by `DraggableModifier.paint` (`DN-X` item 2).
    func capturingDragSnapshot(for id: GlobalElementID, _ body: () -> Void) {
        guard let source = frame.dragSourceID, source == id else {
            body()
            return
        }
        let scope = PaintScope(kind: .capture, effect: .identity, entryClipDepth: frame.clipDepth)
        frame.paintScopes.append(scope)
        body()
        frame.paintScopes.removeLast()
        // The last scope to close for the source wins: one source painted by
        // two nested helpers under one id (`Button` over its own `Box`) closes
        // the outer, the superset, last.
        frame.noteDragSnapshot(scope.captures)
    }
}

extension Frame {
    /// Records the source's captured paint for this frame (`DN-J` item 1).
    func noteDragSnapshot(_ captures: [CapturedPrimitive]) {
        dragSnapshot = captures
        dragCapturedPrimitives = captures.count
    }

    /// Replays the drag snapshot after every other paint, ghosts included
    /// (`DN-J` items 1–2): this frame's capture, else the session's last one
    /// (`DN-H` item 4), translated by `dragPreviewTranslation`, at alpha × 0.7,
    /// on a layer above every layer the frame used. A primitive whose clip was
    /// pushed inside the source keeps that clip, translated with it (a clipped
    /// or rounded draggable replays only what it showed); every other primitive
    /// is masked to the snapshot's own translated bounds (a source half-clipped
    /// by a scroller shows whole) — `DN-Y`. Nothing without a session.
    func paintDragPreview() {
        guard dragSourceID != nil else { return }
        let snapshot = dragSnapshot ?? previousDragSnapshot
        guard let first = snapshot.first else { return }
        let effect = RenderEffect(alpha: Self.dragPreviewOpacity,
                                  affine: .translation(x: Double(dragPreviewTranslation.x.value * scaleFactor),
                                                       y: Double(dragPreviewTranslation.y.value * scaleFactor)))
        let union = snapshot.dropFirst().reduce(first.screenBounds) { $0.union($1.screenBounds) }
        let mask = effect.map(union)
        let layer = (scene.highestLayer ?? 0) + 1
        for primitive in snapshot {
            guard let moved = effect.apply(to: primitive, flattens: true, outer: nil) else { continue }
            insertIntoScene(moved.replayed(mask: mask, layer: layer))
        }
    }

    /// The preview's opacity — MetalUI's reading of `P18`/`P18b` (`DN-J` item 2).
    static let dragPreviewOpacity: Float = 0.7
}

extension CapturedPrimitive {
    /// This primitive on `layer`: a primitive captured with an inner mask keeps
    /// its own (already moved by `RenderEffect.apply`); any other is masked
    /// to `mask` with square corners (`DN-Y`). A transformed primitive keeps
    /// its local mask and has its OUTER mask replaced instead, unless that was
    /// pushed inside the source too (`GX-G`).
    func replayed(mask: MUIBounds, layer: Int) -> CapturedPrimitive {
        let square = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
        var p = self
        p.layer = layer
        if var t = p.transform {
            if !outerMaskInner { t.outerMask = mask; t.outerMaskRadii = square }
            p.transform = t
            return p
        }
        guard !innerMask else { return p }
        switch p.kind {
        case .rect(var r):
            r.contentMask = mask; r.maskCornerRadii = square
            p.kind = .rect(r)
        case .glyph(var g):
            g.contentMask = mask; g.maskCornerRadii = square
            p.kind = .glyph(g)
        case .image(var i, let texture):
            i.contentMask = mask; i.maskCornerRadii = square
            p.kind = .image(i, texture: texture)
        case .surface(var q, let target):
            q.contentMask = mask; q.maskCornerRadii = square
            p.kind = .surface(q, target: target)
        case .path(var path):
            path.contentMask = mask; path.maskCornerRadii = square
            p.kind = .path(path)
        case .shadow(var shadow):
            shadow.contentMask = mask; shadow.maskCornerRadii = square
            p.kind = .shadow(shadow)
        case .gradient(var gradient):
            gradient.contentMask = mask; gradient.maskCornerRadii = square
            p.kind = .gradient(gradient)
        case .blur(var blur):
            blur.contentMask = mask; blur.maskCornerRadii = square
            p.kind = .blur(blur)
        }
        return p
    }
}

extension MUIBounds {
    /// The smallest bounds holding both.
    func union(_ other: MUIBounds) -> MUIBounds {
        let minX = min(origin.x, other.origin.x), minY = min(origin.y, other.origin.y)
        let maxX = max(origin.x + size.width, other.origin.x + other.size.width)
        let maxY = max(origin.y + size.height, other.origin.y + other.size.height)
        return MUIBounds(origin: MUIPoint(x: minX, y: minY), size: MUISize(width: maxX - minX, height: maxY - minY))
    }
}
