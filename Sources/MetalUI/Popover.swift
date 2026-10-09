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

    /// What `requestLayout` hands the later phases: the anchor's layout and
    /// the popover's slot, its layout and (once prepainted) its prepaint.
    public struct Layout {
        var content: Content.GroupLayout
        var slot: PopoverSlot<PopoverContent>
        var slotLayout: PopoverSlot<PopoverContent>.GroupLayout
        var slotPrepaint: PopoverSlot<PopoverContent>.GroupPrepaint?
    }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestGroupLayout(under: id, at: &cursor, pass: &pass)
        precondition(children.count == 1, "a popover modifier requires one child")
        let (slot, slotLayout) = layOutPopover(id, at: &cursor, pass: &pass)
        return (children[0], Layout(content: contentLayout, slot: slot, slotLayout: slotLayout, slotPrepaint: nil))
    }

    /// The popover's slot at `cursor` (1): an evaluated optional produced only
    /// while presented **and** the last frame recorded this wrapper's anchor
    /// (`MN-M` item 2) — a presentation with no anchor yet asks for one more
    /// frame and appears on it. Its placeholder joins no parent: this wrapper
    /// hands its parent the anchor's node alone (`DN-Y` item 2's footing).
    func layOutPopover(_ id: GlobalElementID, at cursor: inout Int,
                       pass: inout LayoutPass) -> (PopoverSlot<PopoverContent>, PopoverSlot<PopoverContent>.GroupLayout) {
        let frame = pass.frame
        var slot = PopoverSlot<PopoverContent>(nil)
        if let (name, body) = presented() {
            if let anchor = frame.previousPresentationAnchors[id] {
                slot = PopoverSlot(AnchoredPresentation(content: Self.chrome(body, name: name), owner: id,
                                                        anchor: anchor, edge: edge, dismiss: dismiss))
            } else {
                frame.requestAnotherFrame()
            }
        }
        let (_, layout) = slot.requestGroupLayout(under: id, at: &cursor, pass: &pass)
        return (slot, layout)
    }

    /// The chrome's box (`MN-M` item 5): the content padded by 12, named by
    /// `item:`'s id (`ID-R`), published as a `.popover` node (`MN-O`). Its
    /// panel — a `.surface` rounded rectangle (radius 10) with a 1-pt
    /// `.separator` border and the default shadow — is painted by
    /// `AnchoredPresentation` as one bordered rect (a legacy `Box` would paint
    /// its fill and border as two primitives, each with its own shadow).
    static func chrome(_ body: PopoverContent, name: String?) -> Box<PopoverContent> {
        var box = Box(content: body)
        box.style.padding = Edges(all: .pixels(Pixels(PopoverChrome.padding)))
        box.elementID = name.map { ElementID($0) }
        box.handlers.axNode.popoverHint = true
        return box
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        let result = content.prepaintGroup(layout: &layout.content, pass: &pass)
        // The anchor map (`MN-M` item 2): this frame's bounds, for the next
        // frame's placement. A presented popover whose anchor moved asks for
        // one more frame, which places it at the new bounds.
        let frame = pass.frame
        let previous = frame.previousPresentationAnchors[id]
        frame.recordPresentationAnchor(id, bounds: bounds)
        if layout.slot.wrapped != nil, let previous, frame.presentationAnchors[id] != previous {
            frame.requestAnotherFrame()
        }
        var slot = layout.slot
        var slotLayout = layout.slotLayout
        let slotPrepaint = slot.prepaintGroup(layout: &slotLayout, pass: &pass)
        layout.slot = slot
        layout.slotLayout = slotLayout
        layout.slotPrepaint = slotPrepaint
        return result
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
        if var slotPrepaint = layout.slotPrepaint {
            layout.slot.paintGroup(layout: &layout.slotLayout, prepaint: &slotPrepaint, pass: &pass)
            layout.slotPrepaint = slotPrepaint
        }
    }
}

extension PopoverModifier: ProposalElementGroup, ProposalElement where Content: ProposalElementGroup {
    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        precondition(children.count == 1, "a popover modifier requires one native child")
        let (slot, slotLayout) = layOutPopover(id, at: &cursor, pass: &pass)
        return (children[0], Layout(content: contentLayout, slot: slot, slotLayout: slotLayout, slotPrepaint: nil))
    }
}

/// A popover's slot: an evaluated optional (`ID-C`) holding the anchored
/// presentation of the chrome.
typealias PopoverSlot<P: ElementGroup> = OptionalGroup<AnchoredPresentation<Box<P>>>

/// The chrome's look (`MN-M` item 5), every constant here.
enum PopoverChrome {
    static let cornerRadius: Float = 10
    static let padding: Float = 12
    static let shadowRadius: Float = 8
    static let shadowY: Float = 2
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

// MARK: - Window's popover stage (spec §3.8)

extension Window {
    /// The popovers' stage (rulings `MN-N`, `MN-Y`), between the open menu's
    /// and the context menu's:
    ///
    /// - a press (any button) walks the open popovers topmost first and,
    ///   while the point is outside the current one, dismisses it — the
    ///   binding written from input under its declarer's dispatch (`ID-F`) —
    ///   then **passes on** to the rest of dispatch (P4a, `MN-Y` item 1),
    ///   unless it landed on a dismissed popover's own anchor: that press is
    ///   consumed with its release, so a toggling anchor closes (`MN-Y` item 2);
    /// - Escape with no modifiers dismisses the topmost popover, before the
    ///   keymap (`MN-N` item 2).
    func dispatchPopovers(_ event: InputEvent) -> Bool {
        switch event {
        case .mouseUp where popoverClaimsRelease == false, .rightMouseUp where popoverClaimsRelease == true:
            popoverClaimsRelease = nil
            return true
        case .mouseDown(let mouse), .rightMouseDown(let mouse):
            var onAnchor = false
            while let top = lastOpenPopovers.last, !top.bounds.contains(mouse.position) {
                lastOpenPopovers.removeLast()
                StateDispatch.dispatching(to: top.id) { top.dismiss() }
                if top.anchor.contains(mouse.position) { onAnchor = true }
            }
            guard onAnchor else { return false }
            releasePressForMenu()   // never drawn pressed, never a click on release
            if case .rightMouseDown = event { popoverClaimsRelease = true } else { popoverClaimsRelease = false }
            return true
        // An other button's press outside dismisses too (spec §1.4 item 3,
        // `MN-Y` item 1) and always passes on: it clicks nothing, so an
        // anchor has no release to consume.
        case .otherMouseDown(let mouse):
            while let top = lastOpenPopovers.last, !top.bounds.contains(mouse.position) {
                lastOpenPopovers.removeLast()
                StateDispatch.dispatching(to: top.id) { top.dismiss() }
            }
            return false
        case .keyDown(let key) where key.charactersIgnoringModifiers == "\u{1b}" && key.modifiers.isEmpty:
            guard let top = lastOpenPopovers.popLast() else { return false }
            StateDispatch.dispatching(to: top.id) { top.dismiss() }
            return true
        default:
            return false
        }
    }
}
