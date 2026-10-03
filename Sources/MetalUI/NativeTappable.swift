import MetalUICore
import MetalUILayout

/// A proposal-layout wrapper that makes its resolved bounds tappable.
///
/// It contributes no layout node: hit testing is registered in prepaint after
/// native layout has resolved, matching the framework's three-phase contract.
public struct OnTapModifier<Content: ProposalElementGroup>: Element {
    /// The tappable proposal content.
    public var content: Content
    /// Run when a press and release land on the content.
    public var action: @MainActor () -> Void
    /// The fill painted while the pointer is over the content, if any.
    public var hoverColor: ColorToken?
    /// A `.contentShape(_:)` written after the tap (ruling `IX-L`), or `nil`.
    var shape: ContentShape?

    /// Makes `content` a pointer target that runs `action` on a click.
    public init(content: Content, hoverColor: ColorToken? = nil,
                action: @escaping @MainActor () -> Void) {
        self.content = content
        self.action = action
        self.hoverColor = hoverColor
    }

    public struct Layout { var content: Content.GroupLayout }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        precondition(children.count == 1, "a native tappable wrapper requires one native child")
        return (children[0], Layout(content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        var handlers = Handlers()
        handlers.onClick = action
        handlers.contentShape = shape
        // Routes a press like any hitbox, but synthesizes no accessibility node
        // (ruling AB-Y): its proposal-path content records nothing and cannot be
        // labelled, so it would publish an unlabelled button.
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
        if let hoverColor, pass.isHovered(id) {
            pass.opacity(0.22) {
                pass.fill(bounds, color: pass.theme[hoverColor])
            }
        }
    }
}

extension OnTapModifier {
    /// Hit-tests this tap by `shape`'s geometry in its bounds — SwiftUI's
    /// `.contentShape(_:)` on the proposal path (ruling `IX-L`; probe
    /// `swiftui-interaction` `C2`, `C10`). **Written after the tap**, on the
    /// wrapper that owns the hitbox: a proposal element that spells it before
    /// its tap does not compile (guard
    /// `aProposalElementCannotSpellContentShapeBeforeItsTap`). SwiftUI's two
    /// orders agree (`C2`), so the one spelling offered loses no answer.
    public func contentShape<S: Shape>(_ shape: S) -> Self {
        var copy = self
        copy.shape = ContentShape(shape)
        return copy
    }
}

extension ProposalElementGroup {
    /// Registers `action` when this proposal-layout subtree is clicked.
    ///
    /// This is the canonical public spelling for the replacement layout path.
    /// The proposal-only receiver keeps CSS-layout elements from entering a
    /// mixed tree that would otherwise trap during layout registration.
    public func onTap(hoverColor: ColorToken? = nil,
                      _ action: @escaping @MainActor () -> Void) -> OnTapModifier<Self> {
        OnTapModifier(content: self, hoverColor: hoverColor, action: action)
    }

    /// Temporary source-compatible spelling for the native migration surface.
    @available(*, deprecated, renamed: "onTap")
    public func nativeOnTap(hoverColor: ColorToken? = nil,
                            _ action: @escaping @MainActor () -> Void) -> OnTapModifier<Self> {
        onTap(hoverColor: hoverColor, action)
    }
}

/// Temporary source-compatible name for ``OnTapModifier``.
@available(*, deprecated, renamed: "OnTapModifier")
public typealias NativeTappable<Content: ProposalElementGroup> = OnTapModifier<Content>
