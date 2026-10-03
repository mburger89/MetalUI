import MetalUICore
import MetalUILayout
import MetalUIPlatform

// Menus, popovers and tooltips, lane 3 — `.popover` on both vocabularies
// (rulings `MN-L`, `MN-M`, `MN-N`, `MN-O`, `MN-X`, `MN-Y`, `MN-Z`; spec
// `docs/superpowers/specs/2026-10-02-menus-popovers-design.md` §2.6, §3.7,
// §3.8). SwiftUI's side is `docs/probes/swiftui-menus-popovers.swift`, arms
// P1–P7.

/// An anchored popover — what `.popover(isPresented:arrowEdge:content:)` and
/// `.popover(item:arrowEdge:content:)` return (ruling `MN-L`).
///
/// **A wrapper on both vocabularies, one identity level**
/// (`DraggablePreviewModifier`'s recipe, `DN-J` item 3): `content` numbers
/// from 0 under its id and the popover's slot is cursor 1 — never `-1`, which
/// is `.overlay`'s (`MC-P`) — so only a caller of `.popover` gets a new level
/// and no existing id moves.
public struct PopoverModifier<Content: ElementGroup, PopoverContent: ElementGroup>: Element {
    /// The anchor: the element the popover points at.
    public var content: Content
    /// The popover's content and the name its chrome takes (`item:`'s id), or
    /// `nil` while dismissed — read fresh at each layout.
    var presented: @MainActor () -> (name: String?, content: PopoverContent)?
    /// Writes the binding `false` (or `nil`), from input (`MN-N`).
    var dismiss: @MainActor () -> Void
    /// The resolved edge (`nil` is `.top`, P7).
    var edge: Edge

    init(content: Content, edge: Edge?, presented: @escaping @MainActor () -> (name: String?, content: PopoverContent)?,
         dismiss: @escaping @MainActor () -> Void) {
        self.content = content
        self.edge = edge ?? .top
        self.presented = presented
        self.dismiss = dismiss
    }

    /// What `requestLayout` hands the later phases (lane 3's red stub: the
    /// anchor alone, no popover).
    public struct Layout {
        var content: Content.GroupLayout
    }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestGroupLayout(under: id, at: &cursor, pass: &pass)
        precondition(children.count == 1, "a popover modifier requires one child")
        return (children[0], Layout(content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

extension PopoverModifier: ProposalElementGroup, ProposalElement where Content: ProposalElementGroup {
    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        precondition(children.count == 1, "a popover modifier requires one native child")
        return (children[0], Layout(content: contentLayout))
    }
}

/// `isPresented:`'s presentation: the content while the binding is `true`.
private func presenting<P>(_ isPresented: Binding<Bool>, _ content: @escaping @MainActor () -> P)
    -> @MainActor () -> (name: String?, content: P)? {
    { isPresented.wrappedValue ? (nil, content()) : nil }
}

/// `item:`'s presentation: the item's content, named by its id (`ID-R`).
private func presenting<Item: Identifiable, P>(_ item: Binding<Item?>, _ content: @escaping @MainActor (Item) -> P)
    -> @MainActor () -> (name: String?, content: P)? {
    { item.wrappedValue.map { ("\($0.id)", content($0)) } }
}

extension StyledElement {
    /// Presents `content` in a popover anchored to this element while
    /// `isPresented` is `true` — SwiftUI's `popover(isPresented:arrowEdge:content:)`
    /// (rulings `MN-L`, `MN-X`; probe arms P1, P7).
    ///
    /// **Placement** (`MN-M`): on `arrowEdge`'s side of this element, 8 pt
    /// away, centred along the other axis; `nil` is `.top`, SwiftUI's default
    /// on macOS (P7). It flips to the opposite edge when it does not fit
    /// inside the window and does there, and is then clamped inside the
    /// window with an 8-pt margin — divergence 111: SwiftUI's popover is its
    /// own window, extends past the presenting one and flips against the
    /// screen (P1, P5). **No arrow is drawn** (divergence 112): the chrome is a
    /// `.surface` rounded rectangle (radius 10) with a `.separator` border and
    /// the default shadow, its content padded by 12.
    ///
    /// **Dismissal** (`MN-N`, `MN-Y`): a press outside every open popover
    /// writes `isPresented` `false` from input and then reaches what it lands
    /// on (P4a); a press on this element itself dismisses and is consumed, so
    /// a toggling `Button` closes the popover; Escape dismisses the topmost
    /// popover before the keymap sees it. A press, wheel or drop on the
    /// popover never reaches what lies beneath it (`MN-Z`).
    ///
    /// The popover is a presentation on a higher layer, laid out against the
    /// window (`LR-CH`'s footing), published as a `.popover` node that
    /// isolates nothing (`MN-O`; P2, P2b). Its content's `@State` starts fresh
    /// at each presentation (`ID-C`). One identity level, for its caller only
    /// (`PopoverModifier`). It appears on the frame after this element was
    /// first laid out, and follows it within one frame when it moves.
    public func popover<P: ElementGroup>(isPresented: Binding<Bool>, arrowEdge: Edge? = nil,
                                         @ElementBuilder content: @escaping @MainActor () -> P)
        -> PopoverModifier<Self, P> {
        PopoverModifier(content: self, edge: arrowEdge, presented: presenting(isPresented, content),
                        dismiss: { isPresented.wrappedValue = false })
    }

    /// Presents a popover built from `item` while it is non-`nil` — SwiftUI's
    /// `popover(item:arrowEdge:content:)` (`MN-L` item 1; probe arm P6). A
    /// different item's id starts its content fresh (`ID-R`); dismissal writes
    /// `nil`. Everything else is `popover(isPresented:arrowEdge:content:)`'s.
    public func popover<Item: Identifiable, P: ElementGroup>(item: Binding<Item?>, arrowEdge: Edge? = nil,
                                                             @ElementBuilder content: @escaping @MainActor (Item) -> P)
        -> PopoverModifier<Self, P> {
        PopoverModifier(content: self, edge: arrowEdge, presented: presenting(item, content),
                        dismiss: { item.wrappedValue = nil })
    }
}

extension ProposalElementGroup {
    /// `StyledElement.popover(isPresented:arrowEdge:content:)` on the proposal
    /// path: the same wrapper, one identity level (`MN-L` item 2).
    public func popover<P: ElementGroup>(isPresented: Binding<Bool>, arrowEdge: Edge? = nil,
                                         @ElementBuilder content: @escaping @MainActor () -> P)
        -> PopoverModifier<Self, P> {
        PopoverModifier(content: self, edge: arrowEdge, presented: presenting(isPresented, content),
                        dismiss: { isPresented.wrappedValue = false })
    }

    /// `StyledElement.popover(item:arrowEdge:content:)` on the proposal path.
    public func popover<Item: Identifiable, P: ElementGroup>(item: Binding<Item?>, arrowEdge: Edge? = nil,
                                                             @ElementBuilder content: @escaping @MainActor (Item) -> P)
        -> PopoverModifier<Self, P> {
        PopoverModifier(content: self, edge: arrowEdge, presented: presenting(item, content),
                        dismiss: { item.wrappedValue = nil })
    }
}
