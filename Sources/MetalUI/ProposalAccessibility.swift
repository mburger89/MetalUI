import MetalUICore
import MetalUILayout

// Plan task 12, part 2, lane 2 (spec `2026-09-29-accessibility-design.md` §4,
// §5; ruling `IX-AB` item 2): the accessibility modifiers on the proposal path.

/// A proposal-layout wrapper carrying accessibility declarations over its one
/// child — `GestureModifier`'s shape (`IX-AB` item 2). It contributes no layout
/// node; its one child numbers from 0 under its id, so the wrapper is **one
/// identity level**, gained only by a caller who writes it. A chain of these
/// modifiers merges into one wrapper (the overloads below return `Self`), so
/// `.accessibilityLabel("L").accessibilityHint("H")` is one level, and on one
/// wrapper the later-written declaration wins, as on a `StyledElement`.
///
/// **Requires exactly one child node** (`SA-G`, as every single-child proposal
/// wrapper does): over zero or several it traps naming the count.
public struct AccessibilityModifier<Content: ProposalElementGroup>: Element {
    public var content: Content
    /// The declarations, as a `StyledElement` carries them in `Handlers`.
    var handlers = Handlers()

    init(content: Content) {
        self.content = content
    }

    public struct Layout { var content: Content.GroupLayout }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        precondition(children.count == 1,
                     "an accessibility modifier requires exactly one native child, got \(children.count) (SA-G)")
        return (children[0], Layout(content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        // A decorative image publishes nothing, even labelled (SwiftUI I4): a
        // declaration over one is dropped with it.
        if let image = content as? Image, image.isDecorative {
            return pass.frame.withAccessibilitySuppressed(except: nil) {
                content.prepaintGroup(layout: &layout.content, pass: &pass)
            }
        }
        // `accessibilityHidden(true)`: the suppression scope around the
        // wrapper's own registration and its content (`IX-W` item 1), as
        // `PrepaintPass.registerAndScope` opens it for a `StyledElement`.
        guard handlers.axNode.declarations.isHidden else { return registerAndPrepaint(id, bounds, &layout, &pass) }
        return pass.frame.withAccessibilitySuppressed(except: nil) {
            registerAndPrepaint(id, bounds, &layout, &pass)
        }
    }

    /// The declared node and actions through `registerHandlers` — so a declared
    /// node writes one `$ax` slot (AB-U) and an action registers behind the one
    /// disabled gate — then the content. **Synthesizing**, so an adjustable
    /// action alone records; the wrapper has no click, no focus and no text of
    /// its own, so nothing else is synthesized, and it registers no hitbox.
    private mutating func registerAndPrepaint(_ id: GlobalElementID, _ bounds: Bounds<Pixels>,
                                              _ layout: inout Layout,
                                              _ pass: inout PrepaintPass) -> Content.GroupPrepaint {
        pass.registerHandlers(handlers, at: bounds, id: id, accessibleText: nil, synthesizesAccessibility: true)
        return content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }

    func declaring(_ change: (inout Handlers) -> Void) -> Self {
        var copy = self
        change(&copy.handlers)
        return copy
    }
}

extension AccessibilityModifier: ProposalElement {}

/// The declarations, shared by the two overload sets below: one body each, so
/// the wrapper and a chain of it cannot write different fields.
extension Handlers {
    mutating func declareAccessibilityLabel(_ label: String) { axNode.label = label }
    mutating func declareAccessibilityValue(_ value: String) { axNode.value = value }
    mutating func declareAdjustableAction(_ handler: @escaping @MainActor (AccessibilityAdjustmentDirection) -> Void) {
        actions[ObjectIdentifier(AccessibilityAdjustment.self)] = { action in
            handler((action as! AccessibilityAdjustment).direction)
        }
    }
    mutating func declareDefaultAction(_ handler: @escaping @MainActor () -> Void) {
        actions[ObjectIdentifier(AccessibilityDefaultAction.self)] = { _ in handler() }
    }
    mutating func addAccessibilityTraits(_ traits: AccessibilityTraits) {
        axNode.declarations.addedTraits.formUnion(traits)
        axNode.declarations.removedTraits.subtract(traits)
    }
    mutating func removeAccessibilityTraits(_ traits: AccessibilityTraits) {
        axNode.declarations.removedTraits.formUnion(traits)
        axNode.declarations.addedTraits.subtract(traits)
    }
}

extension ProposalElementGroup {
    func accessibilityWrapper(_ change: (inout Handlers) -> Void) -> AccessibilityModifier<Self> {
        AccessibilityModifier(content: self).declaring(change)
    }

    /// `StyledElement.accessibilityLabel(_:)` on the proposal path (`IX-AB`
    /// item 2): distributed from a stack to its texts, as SwiftUI's (P3).
    public func accessibilityLabel(_ label: String) -> AccessibilityModifier<Self> {
        accessibilityWrapper { $0.declareAccessibilityLabel(label) }
    }
    /// `StyledElement.accessibilityValue(_:)` on the proposal path.
    public func accessibilityValue(_ value: String) -> AccessibilityModifier<Self> {
        accessibilityWrapper { $0.declareAccessibilityValue(value) }
    }
    /// `StyledElement.accessibilityAdjustableAction(_:)` on the proposal path.
    public func accessibilityAdjustableAction(
        _ handler: @escaping @MainActor (AccessibilityAdjustmentDirection) -> Void) -> AccessibilityModifier<Self> {
        accessibilityWrapper { $0.declareAdjustableAction(handler) }
    }
    /// `StyledElement.accessibilityElement(children:)` on the proposal path.
    public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> AccessibilityModifier<Self> {
        accessibilityWrapper { $0.axNode.declarations.childBehavior = children }
    }
    /// `StyledElement.accessibilityHidden(_:)` on the proposal path.
    public func accessibilityHidden(_ hidden: Bool) -> AccessibilityModifier<Self> {
        accessibilityWrapper { $0.axNode.declarations.isHidden = hidden }
    }
    /// `StyledElement.accessibilityHint(_:)` on the proposal path.
    public func accessibilityHint(_ hint: String) -> AccessibilityModifier<Self> {
        accessibilityWrapper { $0.axNode.declarations.hint = hint }
    }
    /// `StyledElement.accessibilityIdentifier(_:)` on the proposal path.
    public func accessibilityIdentifier(_ identifier: String) -> AccessibilityModifier<Self> {
        accessibilityWrapper { $0.axNode.declarations.identifier = identifier }
    }
    /// `StyledElement.accessibilityAddTraits(_:)` on the proposal path.
    public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> AccessibilityModifier<Self> {
        accessibilityWrapper { $0.addAccessibilityTraits(traits) }
    }
    /// `StyledElement.accessibilityRemoveTraits(_:)` on the proposal path.
    public func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> AccessibilityModifier<Self> {
        accessibilityWrapper { $0.removeAccessibilityTraits(traits) }
    }
    /// `StyledElement.accessibilityAction(_:)` on the proposal path: over a
    /// stack it is distributed to each text (A5), over a tap it runs instead of
    /// the tap (G6).
    public func accessibilityAction(_ handler: @escaping @MainActor () -> Void) -> AccessibilityModifier<Self> {
        accessibilityWrapper { $0.declareDefaultAction(handler) }
    }
    /// `StyledElement.accessibilityAction(named:_:)` on the proposal path.
    public func accessibilityAction(named name: String,
                                    _ handler: @escaping @MainActor () -> Void) -> AccessibilityModifier<Self> {
        accessibilityWrapper { $0.declareNamedAccessibilityAction(name, handler) }
    }
}

/// A chain of accessibility modifiers merges into ONE wrapper — one identity
/// level, and the later-written declaration wins on it, as on a `StyledElement`
/// (H4). These are the concrete type's own members, so they win overload
/// resolution over the `ProposalElementGroup` extension's.
extension AccessibilityModifier {
    public func accessibilityLabel(_ label: String) -> Self { declaring { $0.declareAccessibilityLabel(label) } }
    public func accessibilityValue(_ value: String) -> Self { declaring { $0.declareAccessibilityValue(value) } }
    public func accessibilityAdjustableAction(
        _ handler: @escaping @MainActor (AccessibilityAdjustmentDirection) -> Void) -> Self {
        declaring { $0.declareAdjustableAction(handler) }
    }
    public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> Self {
        declaring { $0.axNode.declarations.childBehavior = children }
    }
    public func accessibilityHidden(_ hidden: Bool) -> Self { declaring { $0.axNode.declarations.isHidden = hidden } }
    public func accessibilityHint(_ hint: String) -> Self { declaring { $0.axNode.declarations.hint = hint } }
    public func accessibilityIdentifier(_ identifier: String) -> Self {
        declaring { $0.axNode.declarations.identifier = identifier }
    }
    public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> Self {
        declaring { $0.addAccessibilityTraits(traits) }
    }
    public func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> Self {
        declaring { $0.removeAccessibilityTraits(traits) }
    }
    public func accessibilityAction(_ handler: @escaping @MainActor () -> Void) -> Self {
        declaring { $0.declareDefaultAction(handler) }
    }
    public func accessibilityAction(named name: String, _ handler: @escaping @MainActor () -> Void) -> Self {
        declaring { $0.declareNamedAccessibilityAction(name, handler) }
    }
}
