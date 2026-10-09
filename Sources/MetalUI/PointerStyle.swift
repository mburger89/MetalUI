import MetalUICore
import MetalUILayout
import MetalUIPlatform

// The pointer style (rulings `CI-H`, `CI-Q`, `CI-S`; spec
// `docs/superpowers/specs/2026-10-08-input-apis-design.md` §1.3, §1.4). SwiftUI's
// `pointerStyle(_:)` (macOS 15) as the probe `swiftui-input-apis.swift` measured
// it (`P0`–`P19`): a non-opaque style region per element, resolved through the
// one ranking (`topmostHitbox`), the innermost style winning, sent to the
// platform only on a change.

/// The shape of the pointer over an element — SwiftUI's `PointerStyle` (ruling
/// `CI-H` item 1). Set with `pointerStyle(_:)`; the window resolves the style
/// under the pointer and asks the platform for the matching cursor.
///
/// SDL has no hand or zoom cursor: there both grab styles show its move cursor
/// and both zooms its default arrow (a documented platform constraint, `CI-H`
/// item 8). `image`, `shape`, `columnResize(directions:)` and
/// `rowResize(directions:)` are not offered (`CI-A`).
public struct PointerStyle: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case arrow, horizontalText, verticalText, rectSelection, grabIdle, grabActive, link
        case zoomIn, zoomOut, columnResize, rowResize
        case frameResize(FrameResizePosition, FrameResizeDirection.Set)
    }

    let kind: Kind

    init(_ kind: Kind) { self.kind = kind }

    /// The platform's default pointer — the arrow.
    public static let `default` = PointerStyle(.arrow)
    /// The I-beam for horizontal text.
    public static let horizontalText = PointerStyle(.horizontalText)
    /// The I-beam for vertical text.
    public static let verticalText = PointerStyle(.verticalText)
    /// The crosshair, for selecting a rectangle (SwiftUI has no `.crosshair`;
    /// this is it, probe `P2`).
    public static let rectSelection = PointerStyle(.rectSelection)
    /// An open hand: something here can be grabbed and dragged.
    public static let grabIdle = PointerStyle(.grabIdle)
    /// A closed hand: something is being dragged.
    public static let grabActive = PointerStyle(.grabActive)
    /// A pointing hand, for a link.
    public static let link = PointerStyle(.link)
    /// A magnifying glass with a plus.
    public static let zoomIn = PointerStyle(.zoomIn)
    /// A magnifying glass with a minus.
    public static let zoomOut = PointerStyle(.zoomOut)
    /// A left-right resize, for a column divider.
    public static let columnResize = PointerStyle(.columnResize)
    /// An up-down resize, for a row divider.
    public static let rowResize = PointerStyle(.rowResize)

    /// The resize pointer for the edge or corner of a frame at `position`,
    /// its arrows showing the `directions` that edge can move — SwiftUI's
    /// `frameResize(position:directions:)`.
    public static func frameResize(position: FrameResizePosition,
                                   directions: FrameResizeDirection.Set = .all) -> PointerStyle {
        PointerStyle(.frameResize(position, directions))
    }

    /// The seam's cursor kind for this style (`CI-H` item 8).
    var platformStyle: PlatformPointerStyle {
        switch kind {
        case .arrow: .arrow
        case .horizontalText: .iBeam
        case .verticalText: .verticalIBeam
        case .rectSelection: .crosshair
        case .grabIdle: .openHand
        case .grabActive: .closedHand
        case .link: .pointingHand
        case .zoomIn: .zoomIn
        case .zoomOut: .zoomOut
        case .columnResize: .columnResize
        case .rowResize: .rowResize
        case .frameResize(let position, let directions):
            .frameResize(edge: position.platformEdge,
                         inward: directions.contains(.inward), outward: directions.contains(.outward))
        }
    }
}

/// An edge or corner of a resizable frame — SwiftUI's `FrameResizePosition`, in
/// the layout direction (`leading` is the left in a left-to-right layout).
public enum FrameResizePosition: Sendable, Hashable {
    /// The top edge.
    case top
    /// The leading edge.
    case leading
    /// The bottom edge.
    case bottom
    /// The trailing edge.
    case trailing
    /// The top-leading corner.
    case topLeading
    /// The top-trailing corner.
    case topTrailing
    /// The bottom-leading corner.
    case bottomLeading
    /// The bottom-trailing corner.
    case bottomTrailing

    var platformEdge: PlatformResizeEdge {
        switch self {
        case .top: .top
        case .leading: .leading
        case .bottom: .bottom
        case .trailing: .trailing
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }
}

/// A way a frame's edge can move under a resize pointer — SwiftUI's
/// `FrameResizeDirection`.
public enum FrameResizeDirection: Sendable, Hashable {
    /// Towards the frame's centre (the frame shrinks).
    case inward
    /// Away from the frame's centre (the frame grows).
    case outward

    /// A set of directions — SwiftUI's `FrameResizeDirection.Set`.
    public struct Set: OptionSet, Sendable, Hashable {
        /// The set's bits.
        public let rawValue: Int8
        /// The set with these bits.
        public init(rawValue: Int8) { self.rawValue = rawValue }
        /// Inward only.
        public static let inward = Set(rawValue: 1 << 0)
        /// Outward only.
        public static let outward = Set(rawValue: 1 << 1)
        /// Both directions.
        public static let all: Set = [.inward, .outward]
    }
}

/// What `.onScrollWheel` and `.pointerStyle` attach to an element: one class
/// box riding `Handlers.pointer`, the eighteenth member (ruling `CI-Q`: one
/// reference, 472 → 480 bytes, not two members). A later `.onScrollWheel`
/// replaces the wheel handler and keeps the style; a later `.pointerStyle` on
/// the same element keeps an earlier (inner) style — SwiftUI's innermost-wins
/// (`CI-AH` item 2) — and keeps the wheel handler.
final class PointerAttachment {
    let scrollWheel: (@MainActor (ScrollEvent) -> Bool)?
    let style: PointerStyle?

    init(scrollWheel: (@MainActor (ScrollEvent) -> Bool)?, style: PointerStyle?) {
        self.scrollWheel = scrollWheel
        self.style = style
    }

    /// `existing` with its wheel handler replaced by `action`.
    static func wheel(_ action: @escaping @MainActor (ScrollEvent) -> Bool,
                      over existing: PointerAttachment?) -> PointerAttachment {
        PointerAttachment(scrollWheel: action, style: existing?.style)
    }

    /// `existing` with `style` unless it already carries one (the inner
    /// declaration wins, `CI-AH` item 2); `existing` itself for a `nil` style
    /// (`nil` attaches nothing, `CI-H` item 2).
    static func style(_ style: PointerStyle?, over existing: PointerAttachment?) -> PointerAttachment? {
        guard let style, existing?.style == nil else { return existing }
        return PointerAttachment(scrollWheel: existing?.scrollWheel, style: style)
    }
}

extension StyledElement {
    /// Shows `style` as the pointer while it is over this element — SwiftUI's
    /// `pointerStyle(_:)` (ruling `CI-H`).
    ///
    /// The element registers a **non-opaque** pointer-style region at its hit
    /// region (its content shape, if any), so it blocks no click. The style
    /// under the pointer is the **innermost** style region containing it whose
    /// element the topmost target there is or descends from: an opaque target
    /// (a click or gesture target), a hover region or another style region
    /// drawn above covers it, on its own layer; a higher layer (a popover, a
    /// `Deferred`) covers it too. **A shape that only paints covers nothing**
    /// (divergence 141 — SwiftUI's does). Render effects move the region with
    /// the drawing. With no style under the pointer it is `.default`.
    ///
    /// `nil` attaches nothing, so an outer style applies (probe `P12`). On one
    /// element a second `.pointerStyle` does not replace the first: the first
    /// written is the inner, and the inner wins, as nested views do in SwiftUI
    /// (`P11`; `CI-AH` item 2).
    ///
    /// Resolved from input (every pointer event) and after every frame (so
    /// content moving under a still pointer, or a `@State` switch of the style,
    /// shows at once), and sent to the platform only on a change. **During a
    /// press** — a gesture's press, or a secondary or middle button's drag —
    /// the style resolves against the pressed element instead, wherever the
    /// pointer is, so a `.grabActive` set when a drag starts stays while a
    /// fast drag leaves the element (MetalUI's rule, `CI-H` item 6). While an
    /// in-window menu or a drawn alert is up the style is `.default`.
    /// `.disabled(true)`, `.allowsHitTesting(false)` and `.hidden()` withdraw
    /// the region.
    ///
    /// Returns `Self` — no identity level, no `StateTable` entry.
    public func pointerStyle(_ style: PointerStyle?) -> Self {
        var copy = self
        copy.handlers.pointer = PointerAttachment.style(style, over: handlers.pointer)
        return copy
    }
}

extension ProposalElementGroup {
    /// `StyledElement.pointerStyle(_:)` on the proposal path: wraps once in a
    /// `PointerStyleModifier` — one identity level, for its caller only
    /// (`HoverModifier`'s recipe). `nil` attaches nothing: the wrapper
    /// registers no region and an outer style applies.
    public func pointerStyle(_ style: PointerStyle?) -> PointerStyleModifier<Self> {
        PointerStyleModifier(content: self, attachment: PointerAttachment.style(style, over: nil))
    }
}

/// A proposal wrapper carrying a pointer style — what the proposal
/// `.pointerStyle(_:)` returns (ruling `CI-H` item 2). No layout node of its
/// own, its one child numbered from 0 under its id, one identity level for its
/// caller only. It registers the style region at its own bounds, inside the
/// disabled and `allowsHitTesting` gates.
public struct PointerStyleModifier<Content: ProposalElementGroup>: Element {
    /// The wrapped proposal content.
    public var content: Content
    var attachment: PointerAttachment?

    init(content: Content, attachment: PointerAttachment?) {
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
        precondition(children.count == 1, "a pointer-style modifier requires one native child")
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

extension PointerStyleModifier: ProposalElement {}

// MARK: - Resolution (`CI-H` items 4, 6, 7; `CI-S`)

extension Window {
    /// Resolves the pointer style at `point` (`nil`: the pointer left the
    /// window) against the last frame's hitboxes and sends it to the platform
    /// when it differs from the last one sent (`CI-H` item 7). Called at the
    /// end of `updateHover`, so from every pointer event and after every
    /// adopted frame.
    ///
    /// **Never a second lookup**: the cover is `topmostHitbox(in:at:where:)`
    /// with "opaque, or carries a hover attachment, or carries a pointer style"
    /// as eligibility; the style is the last-registered (innermost) style region
    /// on the cover's layer containing the point whose id the cover is or
    /// descends from (`CI-H` item 4). During a press (`pointerStylePressTarget`)
    /// it is the pressed target's innermost style instead, wherever the pointer
    /// is (`CI-H` item 6), unless `releasing` — the release ends the press.
    /// While an in-window menu or a drawn alert is up it is `.default`.
    ///
    /// **Work** (`SV-U`'s shape): one visit per hitbox (`pointerStyleVisits`),
    /// and none for a frame with no style region.
    ///
    /// **An exit forgets** (`CI-S`): `point == nil` sets the last-sent style to
    /// unknown, so the first pointer event after it sends unconditionally — SDL's
    /// cursor is process-global and survives leaving the window.
    func updatePointerStyle(at point: Point<Pixels>?, releasing: Bool = false) {
        guard let point else {
            resolvedPointerStyle = nil
            return
        }
        let style: PointerStyle
        if hoverIsSuppressed || lastPointerStyleRegionCount == 0 {
            style = .default
        } else if !releasing, let target = pointerStylePressTarget {
            style = pressedPointerStyle(target) ?? .default
        } else {
            style = pointerStyleUnderPointer(point) ?? .default
        }
        guard style != resolvedPointerStyle else { return }
        resolvedPointerStyle = style
        sendPointerStyle(style.platformStyle)
    }

    /// The innermost style region at `point` its cover reaches (`CI-H` item 4).
    private func pointerStyleUnderPointer(_ point: Point<Pixels>) -> PointerStyle? {
        guard let cover = topmostHitbox(in: lastHitboxes, at: point, where: {
            $0.opaque || $0.handlers.hover != nil || $0.handlers.pointer?.style != nil
        }) else { return nil }
        let top = lastHitboxes[cover]
        var found: PointerStyle?
        for region in lastHitboxes {
            pointerStyleVisits += 1
            guard let style = region.handlers.pointer?.style else { continue }
            if region.layer == top.layer, region.contains(point), top.id.isOrDescends(from: region.id) {
                found = style
            }
        }
        return found
    }

    /// The innermost style region on the pressed target's layer whose id the
    /// target is or descends from, wherever the pointer is (`CI-H` item 6).
    private func pressedPointerStyle(_ target: (id: GlobalElementID, layer: Int)) -> PointerStyle? {
        var found: PointerStyle?
        for region in lastHitboxes {
            pointerStyleVisits += 1
            guard let style = region.handlers.pointer?.style else { continue }
            if region.layer == target.layer, target.id.isOrDescends(from: region.id) {
                found = style
            }
        }
        return found
    }
}
