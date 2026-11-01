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
/// item 8). **To show a hand or a magnifier on SDL, supply the art**
/// (`IC-H`): `.pointerStyle(.image(handImage, hotSpot: …))` for the platform
/// that needs it, a 1x bitmap and, for 2x displays, a 2x bitmap with
/// `Image(scale: 2)`; no art is bundled. `shape(_:eoFill:size:hotSpot:fill:outline:)` draws a `Shape`
/// as a cursor (SwiftUI offers `shape` on visionOS only; ruling `BG-K`, divergence 735).
/// `columnResize(directions:)` and `rowResize(directions:)` show a one-way arrow
/// for one direction (`PH-A`); on SDL, which has no one-arrow divider cursor, the
/// nearest is its single-edge resize cursor (`PH-D`).
public struct PointerStyle: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case arrow, horizontalText, verticalText, rectSelection, grabIdle, grabActive, link
        case zoomIn, zoomOut, columnResize, rowResize
        /// A column or row resize that moves one way only (`PH-A`). `columnResize(directions: .all)`
        /// and the empty set are `columnResize` and the arrow, never these.
        case columnResizeOneWay(trailing: Bool)
        case rowResizeOneWay(down: Bool)
        /// The pointer is hidden (`pointerVisibility(.hidden)`, `PH-F`); never a public style.
        case hidden
        case frameResize(FrameResizePosition, FrameResizeDirection.Set)
        case image(PlatformCursorImage)
        /// A shape rasterized by the window at send time (`BG-K`...`BG-M`).
        case shape(ShapeCursorSpec)
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

    /// The column-resize pointer for a divider that can move only in
    /// `directions` — SwiftUI's `columnResize(directions:)` (`PH-A`, probe
    /// `swiftui-pointer-extras.swift` `D1`–`D4`). Both directions (`.all`) is
    /// `columnResize`; one direction shows an arrow towards that side
    /// (`leading` is the left in a left-to-right layout, `D2`); **the empty set
    /// is the arrow** (`D4`), as `PointerStyle.default`.
    public static func columnResize(directions: HorizontalDirection.Set) -> PointerStyle {
        switch (directions.contains(.leading), directions.contains(.trailing)) {
        case (true, true): .columnResize
        case (true, false): PointerStyle(.columnResizeOneWay(trailing: false))
        case (false, true): PointerStyle(.columnResizeOneWay(trailing: true))
        case (false, false): .default
        }
    }

    /// The row-resize pointer for a divider that can move only in
    /// `directions` — SwiftUI's `rowResize(directions:)` (`PH-A`, `D6`–`D9`).
    /// `.all` is `rowResize`; one direction an arrow up or down; **the empty
    /// set is the arrow**.
    public static func rowResize(directions: VerticalDirection.Set) -> PointerStyle {
        switch (directions.contains(.up), directions.contains(.down)) {
        case (true, true): .rowResize
        case (true, false): PointerStyle(.rowResizeOneWay(down: false))
        case (false, true): PointerStyle(.rowResizeOneWay(down: true))
        case (false, false): .default
        }
    }

    /// A pointer drawn from `image`'s bitmap — SwiftUI's
    /// `PointerStyle.image(_:hotSpot:)` (ruling `IC-B`).
    ///
    /// MetalUI's `Image` wraps one `ImageBitmap`, so every `Image` is accepted;
    /// `resizable()`, `interpolation(_:)` and an accessibility label are ignored
    /// — the cursor is the bitmap at its own size (probe `swiftui-image-cursor.swift`
    /// `I5`). **The cursor is `pixels / scale` points** (`Image`'s `scale`: a
    /// 32 px bitmap at scale 2 is 16 pt; the 2x-display recipe, `IC-C`) and
    /// `hotSpot` is a fraction of that size from the top-left (`.center` is the
    /// middle). **A hot spot outside the unit square clamps per axis**
    /// (divergence 465; SDL refuses a hot spot off its surface). The cursor's
    /// identity is the bitmap's, so rebuilding the `Image` every frame sends
    /// one cursor (`IC-F`); two bitmaps with equal pixels are two. A platform
    /// that cannot make the cursor (a size limit, a driver without colour
    /// cursors) leaves the current one.
    public static func image(_ image: Image, hotSpot: UnitPoint) -> PointerStyle {
        let texture = image.bitmap.texture
        let scale = image.scale
        func unit(_ value: Double) -> Float { value.isNaN ? 0 : Float(min(max(value, 0), 1)) }
        let width = Float(texture.width) / scale, height = Float(texture.height) / scale
        return PointerStyle(.image(PlatformCursorImage(
            texture: texture, scale: scale,
            hotSpot: (x: unit(hotSpot.x) * width, y: unit(hotSpot.y) * height))))
    }

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
        case .columnResizeOneWay(let trailing): .columnResizeOneWay(towardTrailing: trailing)
        case .rowResizeOneWay(let down): .rowResizeOneWay(towardDown: down)
        case .hidden: .hidden
        case .frameResize(let position, let directions):
            .frameResize(edge: position.platformEdge,
                         inward: directions.contains(.inward), outward: directions.contains(.outward))
        case .image(let cursor): .image(cursor)
        // A shape is resolved by the window, which owns the cache and knows the scale (`BG-M`); a caller
        // outside the window sees the arrow.
        case .shape: .arrow
        }
    }
}

/// A horizontal direction, in the layout direction — SwiftUI's
/// `HorizontalDirection`. `columnResize(directions:)` takes a set of them.
public enum HorizontalDirection: Int8, CaseIterable, Sendable, Hashable, Codable {
    /// Towards the leading edge (left in a left-to-right layout).
    case leading
    /// Towards the trailing edge (right in a left-to-right layout).
    case trailing

    /// A set of horizontal directions — SwiftUI's `HorizontalDirection.Set`.
    public struct Set: OptionSet, Sendable, Hashable {
        /// The set's bits.
        public let rawValue: Int8
        /// The set with these bits.
        public init(rawValue: Int8) { self.rawValue = rawValue }
        /// Leading only.
        public static let leading = Set(rawValue: 1 << 0)
        /// Trailing only.
        public static let trailing = Set(rawValue: 1 << 1)
        /// Both directions.
        public static let all: Set = [.leading, .trailing]
        /// The set holding `direction` alone.
        public init(_ direction: HorizontalDirection) {
            self = direction == .leading ? .leading : .trailing
        }
    }
}

/// A vertical direction — SwiftUI's `VerticalDirection`. `rowResize(directions:)`
/// takes a set of them.
public enum VerticalDirection: Int8, CaseIterable, Sendable, Hashable, Codable {
    /// Towards the top.
    case up
    /// Towards the bottom.
    case down

    /// A set of vertical directions — SwiftUI's `VerticalDirection.Set`.
    public struct Set: OptionSet, Sendable, Hashable {
        /// The set's bits.
        public let rawValue: Int8
        /// The set with these bits.
        public init(rawValue: Int8) { self.rawValue = rawValue }
        /// Up only.
        public static let up = Set(rawValue: 1 << 0)
        /// Down only.
        public static let down = Set(rawValue: 1 << 1)
        /// Both directions.
        public static let all: Set = [.up, .down]
        /// The set holding `direction` alone.
        public init(_ direction: VerticalDirection) {
            self = direction == .up ? .up : .down
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
    /// `.hidden` or `.visible` from `pointerVisibility(_:)`; `nil` for none and for `.automatic`
    /// (`PH-F`: automatic defers to an outer declaration).
    let visibility: Visibility?

    init(scrollWheel: (@MainActor (ScrollEvent) -> Bool)?, style: PointerStyle?, visibility: Visibility? = nil) {
        self.scrollWheel = scrollWheel
        self.style = style
        self.visibility = visibility
    }

    /// `existing` with its wheel handler replaced by `action`.
    static func wheel(_ action: @escaping @MainActor (ScrollEvent) -> Bool,
                      over existing: PointerAttachment?) -> PointerAttachment {
        PointerAttachment(scrollWheel: action, style: existing?.style, visibility: existing?.visibility)
    }

    /// `existing` with `style` unless it already carries one (the inner
    /// declaration wins, `CI-AH` item 2); `existing` itself for a `nil` style
    /// (`nil` attaches nothing, `CI-H` item 2).
    static func style(_ style: PointerStyle?, over existing: PointerAttachment?) -> PointerAttachment? {
        guard let style, existing?.style == nil else { return existing }
        return PointerAttachment(scrollWheel: existing?.scrollWheel, style: style, visibility: existing?.visibility)
    }

    /// `existing` with `visibility` unless it already carries one (the inner wins, as a style does);
    /// `existing` itself for `.automatic`, which attaches nothing (`PH-F`).
    static func visibility(_ visibility: Visibility, over existing: PointerAttachment?) -> PointerAttachment? {
        guard visibility != .automatic, existing?.visibility == nil else { return existing }
        return PointerAttachment(scrollWheel: existing?.scrollWheel, style: existing?.style, visibility: visibility)
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

    /// Shows or hides the pointer while it is over this element — SwiftUI's
    /// `pointerVisibility(_:)` (macOS 15; `PH-F`, probe
    /// `swiftui-pointer-extras.swift` `V1`–`V9`).
    ///
    /// `.hidden` hides the pointer, `.visible` shows it even where an outer
    /// view hides it, and `.automatic` is the system's choice: it **attaches
    /// nothing**, so an outer declaration applies (`V6`). The innermost
    /// declaration wins (`V5`), the element's region follows `pointerStyle`'s
    /// rules exactly — non-opaque, covered by an opaque target above (`V9`),
    /// withdrawn by `.disabled(true)`, `.allowsHitTesting(false)` and
    /// `.hidden()`, held by a press — and visibility is independent of the
    /// style: a hidden pointer keeps its `pointerStyle` for when it shows again
    /// (`V7`). SwiftUI hides with `NSCursor.hide()` on entering and unhides on
    /// leaving; MetalUI sends the platform a hidden pointer (`PlatformPointerStyle.hidden`):
    /// a transparent cursor on AppKit, `SDL_HideCursor` on SDL (`PH-G`), and
    /// shows the pointer again when it leaves the window.
    ///
    /// Returns `Self` — no identity level, no `StateTable` entry.
    public func pointerVisibility(_ visibility: Visibility) -> Self {
        var copy = self
        copy.handlers.pointer = PointerAttachment.visibility(visibility, over: handlers.pointer)
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

    /// `StyledElement.pointerVisibility(_:)` on the proposal path: wraps once in
    /// a `PointerStyleModifier` (`PH-F`). `.automatic` attaches nothing.
    public func pointerVisibility(_ visibility: Visibility) -> PointerStyleModifier<Self> {
        PointerStyleModifier(content: self, attachment: PointerAttachment.visibility(visibility, over: nil))
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
            // A hidden pointer is shown again when it leaves (`PH-F`, probe `V2`: SwiftUI unhides on leaving).
            if resolvedPointerStyle?.kind == .hidden { sendPointerStyle(.arrow) }
            resolvedPointerStyle = nil
            return
        }
        var found = ResolvedPointer()
        if hoverIsSuppressed || lastPointerStyleRegionCount == 0 {
            // `.default`, visible
        } else if !releasing, let target = pointerStylePressTarget {
            found = pressedPointer(target)
        } else {
            found = pointerUnderPointer(point)
        }
        // Visibility is independent of the style; a hidden pointer is the one resolved value `.hidden`
        // (`PH-F`), so a change of either is a change.
        let style = found.visibility == .hidden ? PointerStyle(.hidden) : (found.style ?? .default)
        guard style != resolvedPointerStyle else { return }
        resolvedPointerStyle = style
        sendPointerStyle(resolvedPlatformStyle(style))
    }

    /// What the pointer regions at a point say: the innermost style and the innermost visibility.
    struct ResolvedPointer {
        var style: PointerStyle?
        var visibility: Visibility?
    }

    /// The innermost style and visibility regions at `point` their cover reaches (`CI-H` item 4, `PH-F`).
    private func pointerUnderPointer(_ point: Point<Pixels>) -> ResolvedPointer {
        guard let cover = topmostHitbox(in: lastHitboxes, at: point, where: {
            $0.opaque || $0.handlers.hover != nil || $0.handlers.pointer?.style != nil
                || $0.handlers.pointer?.visibility != nil
        }) else { return ResolvedPointer() }
        let top = lastHitboxes[cover]
        var found = ResolvedPointer()
        for region in lastHitboxes {
            pointerStyleVisits += 1
            guard let pointer = region.handlers.pointer, pointer.style != nil || pointer.visibility != nil else { continue }
            if region.layer == top.layer, region.contains(point), top.id.isOrDescends(from: region.id) {
                if let style = pointer.style { found.style = style }
                if let visibility = pointer.visibility { found.visibility = visibility }
            }
        }
        return found
    }

    /// The innermost style and visibility on the pressed target's layer whose id the
    /// target is or descends from, wherever the pointer is (`CI-H` item 6).
    private func pressedPointer(_ target: (id: GlobalElementID, layer: Int)) -> ResolvedPointer {
        var found = ResolvedPointer()
        for region in lastHitboxes {
            pointerStyleVisits += 1
            guard let pointer = region.handlers.pointer, pointer.style != nil || pointer.visibility != nil else { continue }
            if region.layer == target.layer, target.id.isOrDescends(from: region.id) {
                if let style = pointer.style { found.style = style }
                if let visibility = pointer.visibility { found.visibility = visibility }
            }
        }
        return found
    }
}
