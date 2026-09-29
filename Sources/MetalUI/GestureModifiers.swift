import MetalUICore
import MetalUILayout

// Plan task 12, part 1, lane 1 — the gesture attachment modifiers (ruling
// `IX-B`): on every `StyledElement`, returning `Self` and APPENDING to
// `Handlers.gestures` (never replacing, unlike `onClick`); on the proposal
// path, each wrapping the receiver in a `GestureModifier`, built as
// `OnTapModifier` is.
//
// **Declaration order is inner to outer** (`IX-D` item 3): a later modifier is
// an outer layer, as a parent is, so `.onTapGesture { a }.onTapGesture { b }`
// runs `a` for a click (`H12`) and a later `.highPriorityGesture` beats an
// earlier gesture (`H14`).

extension StyledElement {
    /// Runs `action` when this element is tapped `count` times — SwiftUI's
    /// `onTapGesture(count:perform:)`. **Not `onClick`**: a tap fails on a
    /// 5-pt move and on a release outside the element, where `onClick` (Button
    /// semantics) allows any excursion (`IX-D` item 2, probe `G2d` vs `B1`).
    public func onTapGesture(count: Int = 1, perform action: @escaping @MainActor () -> Void) -> Self {
        gesture(TapGesture(count: count).onEnded(action))
    }

    /// Runs `action` once the element has been pressed for `minimumDuration`
    /// without moving `maximumDistance` — SwiftUI's
    /// `onLongPressGesture(minimumDuration:maximumDistance:perform:onPressingChanged:)`.
    /// `onPressingChanged` reports `true` at the press and `false` at the
    /// release or failure (`G6e`, `G6f`).
    public func onLongPressGesture(minimumDuration: Double = 0.5, maximumDistance: Pixels = Pixels(10),
                                   perform action: @escaping @MainActor () -> Void,
                                   onPressingChanged: (@MainActor (Bool) -> Void)? = nil) -> Self {
        var long = LongPressGesture(minimumDuration: minimumDuration, maximumDistance: maximumDistance)
            .onEnded { _ in action() }
        long.pressing = onPressingChanged
        return gesture(long)
    }

    /// Attaches `gesture` at normal priority — SwiftUI's `gesture(_:)`.
    public func gesture<G: Gesture>(_ gesture: G) -> Self {
        handling { $0.gestures.append(GestureAttachment(gesture, priority: .normal)) }
    }

    /// Attaches `gesture` so it recognizes beside whatever wins — SwiftUI's
    /// `simultaneousGesture(_:)`; its callback runs first when both end on
    /// one event (`H3`).
    public func simultaneousGesture<G: Gesture>(_ gesture: G) -> Self {
        handling { $0.gestures.append(GestureAttachment(gesture, priority: .simultaneous)) }
    }

    /// Attaches `gesture` ahead of every normal gesture inside it — SwiftUI's
    /// `highPriorityGesture(_:)` (`H2`, `H14`).
    public func highPriorityGesture<G: Gesture>(_ gesture: G) -> Self {
        handling { $0.gestures.append(GestureAttachment(gesture, priority: .high)) }
    }
}

// MARK: - The proposal path

/// A proposal-layout wrapper that recognizes gestures over its resolved bounds
/// — `OnTapModifier`'s shape (`IX-B`). It contributes no layout node; its one
/// child numbers from 0 under its id, so each wrapper is one identity level,
/// and a chain of them nests, outer modifier outermost (`IX-D` item 3).
public struct GestureModifier<Content: ProposalElementGroup>: Element {
    public var content: Content
    var attachment: GestureAttachment
    /// A `.contentShape(_:)` written after the gesture (ruling `IX-L`), or `nil`.
    var shape: ContentShape?

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
        precondition(children.count == 1, "a gesture modifier requires one native child")
        return (children[0], Layout(content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        var handlers = Handlers()
        handlers.gestures = [attachment]
        handlers.contentShape = shape
        // As `OnTapModifier`: routes a press like any hitbox and synthesizes no
        // accessibility node (ruling AB-Y).
        pass.registerHandlers(handlers, at: bounds, id: id, accessibleText: nil,
                              synthesizesAccessibility: false)
        return content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

extension GestureModifier: ProposalElement {}

extension GestureModifier {
    /// `OnTapModifier.contentShape(_:)` for a gesture wrapper (ruling `IX-L`):
    /// written after the gesture, on the wrapper that owns the hitbox.
    public func contentShape<S: Shape>(_ shape: S) -> Self {
        var copy = self
        copy.shape = ContentShape(shape)
        return copy
    }
}

extension ProposalElementGroup {
    /// `StyledElement.onTapGesture(count:perform:)` on the proposal path.
    public func onTapGesture(count: Int = 1,
                             perform action: @escaping @MainActor () -> Void) -> GestureModifier<Self> {
        gesture(TapGesture(count: count).onEnded(action))
    }

    /// `StyledElement.onLongPressGesture(…)` on the proposal path.
    public func onLongPressGesture(minimumDuration: Double = 0.5, maximumDistance: Pixels = Pixels(10),
                                   perform action: @escaping @MainActor () -> Void,
                                   onPressingChanged: (@MainActor (Bool) -> Void)? = nil)
        -> GestureModifier<Self> {
        var long = LongPressGesture(minimumDuration: minimumDuration, maximumDistance: maximumDistance)
            .onEnded { _ in action() }
        long.pressing = onPressingChanged
        return gesture(long)
    }

    /// `StyledElement.gesture(_:)` on the proposal path.
    public func gesture<G: Gesture>(_ gesture: G) -> GestureModifier<Self> {
        GestureModifier(content: self, attachment: GestureAttachment(gesture, priority: .normal))
    }

    /// `StyledElement.simultaneousGesture(_:)` on the proposal path.
    public func simultaneousGesture<G: Gesture>(_ gesture: G) -> GestureModifier<Self> {
        GestureModifier(content: self, attachment: GestureAttachment(gesture, priority: .simultaneous))
    }

    /// `StyledElement.highPriorityGesture(_:)` on the proposal path.
    public func highPriorityGesture<G: Gesture>(_ gesture: G) -> GestureModifier<Self> {
        GestureModifier(content: self, attachment: GestureAttachment(gesture, priority: .high))
    }
}
