import MetalUICore
import MetalUILayout
import MetalUIPlatform

// The scroll wheel on an element (rulings `CI-I`, `CI-AD`, `CI-AH`; spec
// `docs/superpowers/specs/2026-10-08-input-apis-design.md` §1.3, §1.4 item 4).
// **MetalUI-only**: SwiftUI on macOS has no per-view wheel hook (census:
// `onScrollWheel` 0; `onScrollPhaseChange`/`onScrollGeometryChange` observe a
// `ScrollView`). gpui's `on_scroll_wheel` is the comparison. The dispatch — one
// ranking, innermost first, coexisting with `ScrollView` (`DD-Y`) — is
// `Window.applyScroll`.

extension StyledElement {
    /// Runs `action` for a scroll-wheel or trackpad-scroll event over this
    /// element, before any `ScrollView` enclosing it; `action` returns `true`
    /// to **claim** the event or `false` to pass it on (ruling `CI-I`;
    /// MetalUI-only — SwiftUI has no per-view wheel hook on macOS).
    ///
    /// The `ScrollEvent` carries the device's `delta` in points (a notched
    /// wheel's lines × 10; `isPrecise` says which — never transformed by a
    /// render effect), `phase` and `momentumPhase` (a trackpad's gesture and
    /// its glide; `.none` from a wheel and on SDL), `modifiers`, the window
    /// point `position` and **`location`, the pointer in this element's own
    /// space** (its top-leading corner is the origin; a render effect is
    /// undone).
    ///
    /// The element registers a **non-opaque** wheel region at its hit region,
    /// inside the disabled, `allowsHitTesting` and `hidden()` gates. **Dispatch**
    /// (`CI-I` item 4): the topmost opaque target or wheel region under the
    /// pointer, then its ancestors — innermost first, on its layer: at each, a
    /// wheel handler (claims with `true`), then a scroller (always claims).
    /// So a handler **inside** a `ScrollView` that claims stops it, one that
    /// declines lets it scroll, and **a handler on or around a `ScrollView`
    /// sees nothing over it** — the scroller claimed first (written on a
    /// `ScrollView`, the modifier is the scroller's parent; to veto scrolling,
    /// put the handler on its content, `CI-AH` item 1). An opaque target drawn
    /// above that is not inside this element stops the wheel; one inside it
    /// does not. A wheel nothing claims reaches the window's `onInput`, unless
    /// an opaque target was under the pointer — this element's own included:
    /// a declining handler on a click target still stops the wheel, and one
    /// on a `TextEditor` leaves the editor scrolling itself (`CI-AL` item 1).
    ///
    /// `action` runs from input, on the main actor, dispatched to this
    /// element, so `@State` and `Binding` writes are legal. Each event is
    /// dispatched by the pointer at that event — a gliding scroll is not
    /// latched to the element it began over (`CI-AD`).
    ///
    /// Returns `Self` — no identity level, no `StateTable` entry; a later
    /// `.onScrollWheel` replaces this one.
    public func onScrollWheel(perform action: @escaping @MainActor (ScrollEvent) -> Bool) -> Self {
        var copy = self
        copy.handlers.pointer = PointerAttachment.wheel(action, over: handlers.pointer)
        return copy
    }
}

extension ProposalElementGroup {
    /// `StyledElement.onScrollWheel(perform:)` on the proposal path: wraps once
    /// in a `ScrollWheelModifier` — one identity level, for its caller only
    /// (`HoverModifier`'s recipe). Written on a `ProposalScrollView` it is the
    /// scroller's parent and sees nothing over it (`CI-V` item 2).
    public func onScrollWheel(perform action: @escaping @MainActor (ScrollEvent) -> Bool)
        -> ScrollWheelModifier<Self> {
        ScrollWheelModifier(content: self, attachment: PointerAttachment.wheel(action, over: nil))
    }
}

/// A proposal wrapper carrying a scroll-wheel handler — what the proposal
/// `.onScrollWheel(perform:)` returns (ruling `CI-I` item 2). No layout node of
/// its own, its one child numbered from 0 under its id, one identity level for
/// its caller only. It registers the wheel region at its own bounds, inside the
/// disabled and `allowsHitTesting` gates.
public struct ScrollWheelModifier<Content: ProposalElementGroup>: Element {
    /// The wrapped proposal content.
    public var content: Content
    var attachment: PointerAttachment

    init(content: Content, attachment: PointerAttachment) {
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
        precondition(children.count == 1, "a scroll-wheel modifier requires one native child")
        return (children[0], Layout(content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        var handlers = Handlers()
        handlers.pointer = attachment
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

extension ScrollWheelModifier: ProposalElement {}
