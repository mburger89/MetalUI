import MetalUICore
import MetalUILayout
import MetalUIPlatform

// `onHover` and `onContinuousHover` (rulings `SV-N`, `SV-Z`, `SV-U`; spec
// `docs/superpowers/specs/2026-10-04-platform-services-design.md` §2, §4.2).
// SwiftUI's hover is unmeasured (probe `swiftui-platform-services.swift` arms
// `H1`–`H11`, a recorded broken instrument), so the rules are MetalUI's, ruled
// against gpui's model: a non-opaque hover region per element, the hovered set
// found through the one ranking (`topmostHitbox`), callbacks from input and
// after the frame, under `StateDispatch`.

/// Where the pointer is over an element that declared
/// `onContinuousHover(perform:)` — SwiftUI's `HoverPhase` (ruling `SV-N` item
/// 1).
public enum HoverPhase: Equatable, Sendable {
    /// The pointer is over the element, at this point in the element's own
    /// space (its top-leading corner is the origin; a render effect is undone,
    /// so a rotated element reports where on itself the pointer is). Only
    /// `.local` is offered — no `coordinateSpace:` parameter.
    case active(Point<Pixels>)
    /// The pointer left the element, the element stopped being hoverable, or
    /// it left the tree.
    case ended
}

/// What `.onHover`/`.onContinuousHover` attach to an element: one class box
/// riding `Handlers.hover` (`SV-N` item 1, `MN-Q`'s shape). A later `.onHover`
/// replaces an earlier one and keeps the continuous callback, and the reverse.
final class HoverAttachment {
    let onHover: ((Bool) -> Void)?
    let onContinuousHover: ((HoverPhase) -> Void)?

    init(onHover: ((Bool) -> Void)?, onContinuousHover: ((HoverPhase) -> Void)?) {
        self.onHover = onHover
        self.onContinuousHover = onContinuousHover
    }

    /// `existing` with its `onHover` replaced by `action`.
    static func hover(_ action: @escaping (Bool) -> Void, over existing: HoverAttachment?) -> HoverAttachment {
        HoverAttachment(onHover: action, onContinuousHover: existing?.onContinuousHover)
    }

    /// `existing` with its `onContinuousHover` replaced by `action`.
    static func continuous(_ action: @escaping (HoverPhase) -> Void,
                           over existing: HoverAttachment?) -> HoverAttachment {
        HoverAttachment(onHover: existing?.onHover, onContinuousHover: action)
    }
}

extension StyledElement {
    /// Runs `action` with `true` when the pointer enters this element and
    /// `false` when it leaves — SwiftUI's `onHover(perform:)` (ruling `SV-N`).
    ///
    /// The element registers a **non-opaque** hover region at its hit region
    /// (its content shape, if any), so it never blocks a click on what lies
    /// beneath. It is hovered while the pointer is over it and nothing that
    /// covers it is: an opaque target (a click or gesture target) or another
    /// hover region drawn above it — not its own descendants, which hover with
    /// it (nested regions all hover) — on its own layer; a higher layer (a
    /// popover, a `Deferred`) covers it too (`SV-N` item 3, `SV-Z`). A shape
    /// that only paints covers nothing. Render effects move the region with the
    /// drawing (`GX-I`).
    ///
    /// `action` runs from input (pointer moves, presses and releases, the
    /// pointer leaving the window) and after a frame in which content moved,
    /// appeared or left under a still pointer — never in a phase — on the main
    /// actor, dispatched to this element, so `@State` and `Binding` writes are
    /// legal. Leavings run before enterings: innermost first, then outermost
    /// first. An element that leaves the tree while hovered gets `false` after
    /// that frame. `.disabled(true)`, `.allowsHitTesting(false)` and
    /// `.hidden()` withdraw the region; while an in-window menu or a drawn
    /// alert is up nothing is hovered (`SV-N` items 2, 4–6).
    ///
    /// Returns `Self` — no identity level, no `StateTable` entry (`MN-Q`'s
    /// shape); a later `.onHover` replaces this one.
    public func onHover(perform action: @escaping (Bool) -> Void) -> Self {
        var copy = self
        copy.handlers.hover = HoverAttachment.hover(action, over: handlers.hover)
        return copy
    }

    /// Runs `action` with `.active(point)` — the pointer in this element's own
    /// space — on entering and on every pointer move over this element, and
    /// with `.ended` when it leaves: SwiftUI's `onContinuousHover(perform:)`
    /// with the `.local` coordinate space only (ruling `SV-N` item 1). Hovered
    /// exactly when `onHover(perform:)`'s rule says, and run from the same
    /// places; `onHover` and this may be declared together.
    public func onContinuousHover(perform action: @escaping (HoverPhase) -> Void) -> Self {
        var copy = self
        copy.handlers.hover = HoverAttachment.continuous(action, over: handlers.hover)
        return copy
    }
}

extension ProposalElementGroup {
    /// `StyledElement.onHover(perform:)` on the proposal path: wraps once in a
    /// `HoverModifier` — one identity level, for its caller only (`SV-N` item
    /// 1, `MN-Q`'s shape).
    public func onHover(perform action: @escaping (Bool) -> Void) -> HoverModifier<Self> {
        HoverModifier(content: self, attachment: HoverAttachment.hover(action, over: nil))
    }

    /// `StyledElement.onContinuousHover(perform:)` on the proposal path: wraps
    /// once in a `HoverModifier`.
    public func onContinuousHover(perform action: @escaping (HoverPhase) -> Void) -> HoverModifier<Self> {
        HoverModifier(content: self, attachment: HoverAttachment.continuous(action, over: nil))
    }
}

/// A proposal wrapper carrying hover callbacks — what the proposal `.onHover`
/// and `.onContinuousHover` return (ruling `SV-N` item 1). `ContextualModifier`'s
/// recipe: no layout node of its own, its one child numbered from 0 under its
/// id, one identity level for its caller only. It registers the hover region
/// at its own bounds, inside the disabled and `allowsHitTesting` gates.
public struct HoverModifier<Content: ProposalElementGroup>: Element {
    /// The wrapped proposal content.
    public var content: Content
    var attachment: HoverAttachment

    init(content: Content, attachment: HoverAttachment) {
        self.content = content
        self.attachment = attachment
    }

    /// The content's layout.
    public struct Layout { var content: Content.GroupLayout }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        precondition(children.count == 1, "a hover modifier requires one native child")
        return (children[0], Layout(content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        var handlers = Handlers()
        handlers.hover = attachment
        // A wrapper's registration follows an effect written inside it at the
        // same rect (`GX-P` item 1).
        let frame = pass.frame
        return frame.sharingRegistrationsWithEffects(at: bounds, register: {
            pass.registerHandlers(handlers, at: bounds, id: id, accessibleText: nil,
                                  synthesizesAccessibility: false)
        }, content: { content.prepaintGroup(layout: &layout.content, pass: &pass) })
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

extension HoverModifier: ProposalElement {}

// MARK: - The hovered set (`SV-N` items 3–6)

/// One hovered region the window remembers between events: the element, its
/// occurrence among the frame's hover regions with that id, the callbacks of
/// the last frame it was in and the region itself (for the local point).
struct HoveredRegion {
    struct Key: Hashable {
        let id: GlobalElementID
        let occurrence: Int
    }
    let key: Key
    let attachment: HoverAttachment
    let region: Hitbox
}

extension Window {
    /// Recomputes the hovered set at `point` (`nil`: the pointer left the
    /// window) against the last frame's hitboxes and runs every change's
    /// callbacks under `StateDispatch` (rulings `SV-N` items 3–6, `SV-Z`).
    ///
    /// **Never a second lookup**: the cover is `topmostHitbox(in:at:where:)`
    /// with "opaque or carries a hover attachment" as the eligibility; a hover
    /// region is a member when it is on the cover's layer, contains the point
    /// (`Hitbox.contains`, so effects and content shapes apply) and the cover
    /// is it or descends from it. **Work** (`SV-U`): after the ranking, one
    /// visit per hitbox (`hoverVisits`), and nothing at all for a frame with no
    /// hover region and nothing hovered.
    ///
    /// `reportsMoves`: whether `onContinuousHover` hears `.active` from every
    /// member (a pointer event) or only from an entering one (after a frame).
    ///
    /// Then the pointer style is resolved at the same point
    /// (`updatePointerStyle(at:releasing:)`, ruling `CI-H` item 7): its call
    /// sites are this method's. `releasing`: the event is a button's release,
    /// which ends a press's hold on the style (`CI-H` item 6).
    func updateHover(at point: Point<Pixels>?, reportsMoves: Bool, releasing: Bool = false) {
        updateHoveredRegions(at: point, reportsMoves: reportsMoves)
        updatePointerStyle(at: point, releasing: releasing)
    }

    /// The hovered set's half of `updateHover(at:reportsMoves:releasing:)`.
    private func updateHoveredRegions(at point: Point<Pixels>?, reportsMoves: Bool) {
        guard lastHoverRegionCount > 0 || !hoveredRegions.isEmpty else { return }
        var next: [HoveredRegion] = []
        if let point, lastHoverRegionCount > 0, !hoverIsSuppressed,
           let cover = topmostHitbox(in: lastHitboxes, at: point,
                                     where: { $0.opaque || $0.handlers.hover != nil }) {
            let top = lastHitboxes[cover]
            var occurrences: [GlobalElementID: Int] = [:]
            for region in lastHitboxes {
                hoverVisits += 1
                guard let attachment = region.handlers.hover else { continue }
                let occurrence = occurrences[region.id, default: 0]
                occurrences[region.id] = occurrence + 1
                if region.layer == top.layer, region.contains(point), top.id.isOrDescends(from: region.id) {
                    next.append(HoveredRegion(key: HoveredRegion.Key(id: region.id, occurrence: occurrence),
                                              attachment: attachment, region: region))
                }
            }
        }
        let before = Set(hoveredRegions.map(\.key))
        let after = Set(next.map(\.key))
        let leaving = hoveredRegions.filter { !after.contains($0.key) }
        hoveredRegions = next
        // Leavings first, innermost (registered last) first, through the
        // closures of the last frame each was in.
        for region in leaving.reversed() {
            StateDispatch.dispatching(to: region.key.id) {
                region.attachment.onHover?(false)
                region.attachment.onContinuousHover?(.ended)
            }
        }
        // Then enterings, outermost first; continuous moves in the same order.
        guard let point else { return }
        for region in next {
            let entering = !before.contains(region.key)
            guard entering || (reportsMoves && region.attachment.onContinuousHover != nil) else { continue }
            StateDispatch.dispatching(to: region.key.id) {
                if entering { region.attachment.onHover?(true) }
                if let continuous = region.attachment.onContinuousHover {
                    let local = region.region.localPoint(point)
                    continuous(.active(Point(x: Pixels(local.x.value - region.region.origin.x.value),
                                             y: Pixels(local.y.value - region.region.origin.y.value))))
                }
            }
        }
    }

    /// Whether nothing may be hovered: an in-window menu (`MN-F`) or a drawn
    /// alert (`SV-J`) is up (`SV-N` item 6).
    var hoverIsSuppressed: Bool {
        (menuSession.map { !$0.isNative } ?? false) || drawnAlert != nil
    }
}
