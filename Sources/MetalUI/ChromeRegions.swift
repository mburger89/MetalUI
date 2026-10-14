import MetalUICore
import MetalUIPlatform

// SDL custom chrome, lane 1 (ruling `CW-E`). Which rects of the window a platform may move the window from:
// the unclaimed title-bar band (`AS-J`) and each `WindowDragGesture` handle (`WD-C`), minus every hitbox
// that needs the pointer, because a platform hit-test region takes the pointer events inside it away from
// the app (SDL header; divergence 425). **A region function over a hitbox list, not a point lookup**: the
// one ranking `topmostHitbox(in:at:where:)` is untouched (`CW-J`); the subtraction is
// `ChromeHitMap.carve` (`MetalUIPlatform`, portable and tested there).

@MainActor
enum ChromeRegions {
    /// The regions for `hitboxes` (the last frame's), a band `bandHeight` tall across `windowWidth` (none
    /// when 0) plus every handle, carved by every blocker, capped at `ChromeHitSnapshot.maximumRegions`.
    static func compute(hitboxes: [Hitbox], bandHeight: Float, windowWidth: Float) -> [Bounds<Pixels>] {
        // The one ranking's key, `(layer, registration index)` (`topmostHitbox`); a higher one is above.
        func rank(_ index: Int) -> (Int, Int) { (hitboxes[index].layer, index) }
        let blockerIndices = hitboxes.indices.filter { blocks(hitboxes[$0]) }
        var ranked: [(candidate: Bounds<Pixels>, blockers: [Bounds<Pixels>])] = []
        if bandHeight > 0 {
            // The band has no element: everything carves it but a backdrop (`CW-V`), content the bar floats over.
            let band = Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                              size: Size(width: Pixels(windowWidth), height: Pixels(bandHeight)))
            let carving = blockerIndices.map { blockerRect(hitboxes[$0]) }.filter {
                !isBackdrop($0, bandHeight: bandHeight, windowWidth: windowWidth)
            }
            ranked.append((band, carving))
        }
        // A handle under a render effect has its bounds in local space: not a candidate (conservative).
        for index in hitboxes.indices where isHandle(hitboxes[index]) && hitboxes[index].transform == nil {
            // Only a blocker ranked above the handle's own hitbox carves it (`CW-V`).
            let above = blockerIndices.filter { rank($0) > rank(index) }.map { blockerRect(hitboxes[$0]) }
            ranked.append((hitboxes[index].bounds, above))
        }
        return ChromeHitMap.carve(ranked: ranked, limit: ChromeHitSnapshot.maximumRegions).rects
    }

    /// Whether `rect` is content behind the bar rather than in it: as wide as the window and reaching below the
    /// band (`CW-V`). A control in the bar is narrower or ends inside it.
    private static func isBackdrop(_ rect: Bounds<Pixels>, bandHeight: Float, windowWidth: Float) -> Bool {
        rect.origin.x.value <= 0 && rect.origin.x.value + rect.size.width.value >= windowWidth
            && rect.origin.y.value + rect.size.height.value > bandHeight
    }

    /// Whether `hitbox` is a window-drag handle: a hitbox whose only pointer asks are `WindowDragGesture`
    /// leaves. Its rect is a candidate; it is not a blocker.
    static func isHandle(_ hitbox: Hitbox) -> Bool {
        let handlers = hitbox.handlers
        guard !handlers.gestures.isEmpty, handlers.gestures.allSatisfy({ isOnlyWindowDrag($0.node) }) else {
            return false
        }
        return !needsPointer(handlers)
    }

    /// Whether `hitbox` needs the pointer events (`CW-E`): any opaque target (`onClick`, a text field, a
    /// slider's track, a scroller, a gesture) other than a handle, a draggable, a drop destination, a
    /// contextual (secondary press) region. Hover, scroll-wheel, pointer-style and key regions are not
    /// blockers — a hover at the root would forbid all drag — and so lose their pointer events inside a
    /// region (divergence 425).
    static func blocks(_ hitbox: Hitbox) -> Bool {
        let handlers = hitbox.handlers
        if handlers.hasDraggable || handlers.dropDestination != nil || handlers.contextual != nil { return true }
        return hitbox.opaque && !isHandle(hitbox)
    }

    /// What a blocker takes out of the candidates: its clipped rect, or — under a render effect, where the
    /// rect is local — the clip at the effect's entry, which bounds every point the hitbox can be hit at.
    /// One pixel too many blocked, never one too few.
    private static func blockerRect(_ hitbox: Hitbox) -> Bounds<Pixels> {
        hitbox.transform?.outerClip ?? hitbox.bounds
    }

    /// Whether `handlers` ask for the pointer apart from gestures.
    private static func needsPointer(_ handlers: Handlers) -> Bool {
        handlers.onClick != nil || handlers.textInput != nil || handlers.valueTrack != nil
            || handlers.dropDestination != nil || handlers.contextual != nil
    }

    /// Whether every leaf of `node` is a `WindowDragGesture`.
    private static func isOnlyWindowDrag(_ node: GestureNode) -> Bool {
        switch node {
        case .leaf(let leaf):
            if case .windowDrag = leaf.kind { return true }
            return false
        case .exclusive(let children), .simultaneous(let children):
            return children.allSatisfy(isOnlyWindowDrag)
        }
    }
}
