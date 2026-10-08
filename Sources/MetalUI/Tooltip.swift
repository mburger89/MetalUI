import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUITextSystem

// Menus, popovers and tooltips, lane 3 — `.help` and the drawn tooltip
// (rulings `MN-P`, `MN-U`, `MN-V` item 3; spec §3.10). SwiftUI's side is
// `docs/probes/swiftui-menus-popovers.swift`, arms H1–H7: `.help` is exactly
// `accessibilityHint` (H1–H5); the tooltip itself is MetalUI's (H6/H7 found no
// tooltip window in a locked session — divergence 113).

extension StyledElement {
    /// Explains this element — SwiftUI's `help(_:)` (ruling `MN-P`; probe arms
    /// H1–H5).
    ///
    /// **Accessibility** is exactly `accessibilityHint(_:)`'s, through the same
    /// declaration (AppKit `AXHelp`, AccessKit `description`): whichever of the
    /// two is written later wins (H3, H3b), an outer one beats an inner one
    /// (H5) and a plain container distributes it (H4).
    ///
    /// **A tooltip**, drawn by the window on every platform (divergence 113:
    /// on macOS SwiftUI shows AppKit's native one): shown once the pointer has
    /// rested over this element for 1.0 s of display-link time, below the
    /// pointer, flipped and clamped inside the window; hidden by a press, a
    /// wheel event, a key, leaving, or the window leaving key, and back only
    /// after leaving and re-entering. Found by the context menu's own lookup
    /// (`MN-V` item 3): a covering pointer target hides it, a disabled element
    /// still explains itself, `.allowsHitTesting(false)` shows none (`MN-U`).
    /// No pointer target is added. Returns `Self` — no identity level.
    public func help(_ text: String) -> Self {
        handling { handlers in
            handlers.axNode.declarations.hint = text
            handlers.contextual = ContextualAttachment(menu: handlers.contextual?.menu, help: text)
        }
    }
}

extension ProposalElementGroup {
    /// `StyledElement.help(_:)` on the proposal path: wraps once in a
    /// `ContextualModifier` — one identity level, for its caller only
    /// (`MN-Q`), at the same position `accessibilityHint(_:)`'s wrapper takes.
    public func help(_ text: String) -> ContextualModifier<Self> {
        ContextualModifier(content: self, attachment: ContextualAttachment(menu: nil, help: text))
    }
}

/// A tooltip on screen: its text and panel in window points.
struct VisibleTooltip: Equatable {
    let text: String
    let frame: Bounds<Pixels>
}

/// The tooltip's look and placement (`MN-P` item 2), every constant here.
enum TooltipPlacement {
    /// The hover delay, in seconds of display-link time.
    static let delay: Double = 1.0
    /// Below the pointer, so the cursor does not cover it.
    static let below: Float = 18
    /// Between the pointer and a tooltip flipped above it.
    static let aboveGap: Float = 4
    /// The margin a tooltip keeps from the window's edges.
    static let margin: Float = 4
    /// The text's point size.
    static let fontSize: Double = 11
    /// The width the text wraps at.
    static let wrapWidth: Double = 300
    /// The text's inset inside the panel: horizontal, vertical.
    static let paddingX: Float = 6, paddingY: Float = 4
    /// The panel's corner radius.
    static let cornerRadius: Float = 4

    /// The tooltip's font: the default control font at 11 pt.
    @MainActor static var fontDescriptor: FontDescriptor {
        var descriptor = MenuPanel.fontDescriptor
        descriptor.size = fontSize
        return descriptor
    }

    /// The tooltip's origin for a panel of `size` with the pointer at
    /// `pointer` in a `window`-sized window — pure: its top-left corner
    /// `below` the pointer; flipped above it (its bottom `aboveGap` above the
    /// pointer) when it would pass the bottom margin; then clamped inside the
    /// window with `margin`.
    static func origin(pointer: Point<Pixels>, size: Size<Pixels>, window: Size<Pixels>) -> Point<Pixels> {
        let w = size.width.value, h = size.height.value
        var y = pointer.y.value + below
        if y + h > window.height.value - margin { y = pointer.y.value - aboveGap - h }
        let x = max(margin, min(pointer.x.value, window.width.value - margin - w))
        y = max(margin, min(y, window.height.value - margin - h))
        return Point(x: Pixels(x), y: Pixels(y))
    }
}

/// The window's tooltip state (`MN-P` item 2): never `StateTable`, never an
/// element, so no id path or reserved slot moves.
struct TooltipTracker {
    enum Phase: Equatable {
        /// The pointer rests on no help region.
        case idle
        /// Over `region` since `since` — `nil` until the first tick after
        /// entering stamps it (`IX-C`'s "a stamp is always a real tick").
        case pending(region: GlobalElementID, text: String, since: Double?)
        /// On screen.
        case shown(region: GlobalElementID, tooltip: VisibleTooltip)
        /// Hidden over `region` until the pointer leaves it.
        case spent(region: GlobalElementID)
    }

    var phase = Phase.idle
    /// The latest pointer position inside the region.
    var pointer = Point(x: Pixels(0), y: Pixels(0))

    /// The region the phase is about, if any.
    var region: GlobalElementID? {
        switch phase {
        case .idle: nil
        case .pending(let region, _, _), .shown(let region, _), .spent(let region): region
        }
    }

    /// Whether a timer is running — the display link's reason to stay awake.
    var isPending: Bool {
        if case .pending = phase { return true }
        return false
    }

    /// The tooltip on screen, if any.
    var visible: VisibleTooltip? {
        if case .shown(_, let tooltip) = phase { return tooltip }
        return nil
    }

    /// Hides a pending or shown tooltip; its region is spent until left.
    mutating func hide() {
        switch phase {
        case .pending(let region, _, _), .shown(let region, _): phase = .spent(region: region)
        case .idle, .spent: break
        }
    }
}

extension Window {
    /// The tooltip on screen, if any.
    var visibleTooltip: VisibleTooltip? { tooltipTracker.visible }

    /// The tooltip stage (`MN-P` item 2), run for every event before dispatch
    /// and never claiming one: a move finds the help region under the pointer
    /// through the context menu's lookup (`MN-V` item 3) and starts a timer on
    /// entering a new one; a press, a wheel event and a key hide. While a menu
    /// is open every event hides it.
    func trackTooltip(_ event: InputEvent) {
        switch event {
        // A right- or other-button drag is tracked as a primary drag is, and
        // an other-button press hides as the other presses do (ruling `CI-Z`
        // item 2).
        case .mouseMoved(let mouse), .mouseDragged(let mouse), .rightMouseDragged(let mouse),
             .otherMouseDragged(let mouse):
            guard menuSession == nil else {
                tooltipTracker.hide()
                return
            }
            let index = contextualTarget(at: mouse.position, where: { $0.help != nil })
            let region = index.map { lastHitboxes[$0] }
            if let region, region.id == tooltipTracker.region {
                tooltipTracker.pointer = mouse.position
                return
            }
            tooltipTracker.pointer = mouse.position
            if let region, let text = region.handlers.contextual?.help {
                tooltipTracker.phase = .pending(region: region.id, text: text, since: nil)
            } else {
                tooltipTracker.phase = .idle
            }
        case .mouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown:
            tooltipTracker.hide()
        default:
            break
        }
    }

    /// Advances the tooltip's timer to a display-link tick (`MN-P` item 2):
    /// the first tick after entering stamps it; a tick `delay` later shows it
    /// at the latest pointer position. Called from the display link, beside
    /// `advanceGestures`.
    func advanceTooltip(to time: Double) {
        guard case .pending(let region, let text, let since) = tooltipTracker.phase else { return }
        guard let since else {
            tooltipTracker.phase = .pending(region: region, text: text, since: time)
            return
        }
        guard time >= since + TooltipPlacement.delay else { return }
        let font = menuTextSystem.resolveFont(TooltipPlacement.fontDescriptor)
        let measured = menuTextSystem.measure(text, font: font, wrappingAt: TooltipPlacement.wrapWidth)
        let size = Size(width: Pixels(Float(measured.widestLine).rounded(.up) + 2 * TooltipPlacement.paddingX),
                        height: Pixels(Float(measured.totalHeight).rounded(.up) + 2 * TooltipPlacement.paddingY))
        let origin = TooltipPlacement.origin(pointer: tooltipTracker.pointer, size: size, window: contentSizeForDrag)
        tooltipTracker.phase = .shown(region: region, tooltip: VisibleTooltip(text: text,
                                                                              frame: Bounds(origin: origin, size: size)))
        setNeedsRedraw()
    }

    /// Hides the tooltip — the window leaving key (`MN-P` item 2).
    func hideTooltip() {
        guard tooltipTracker.isPending || tooltipTracker.visible != nil else { return }
        tooltipTracker.hide()
        setNeedsRedraw()
    }
}

// MARK: - Paint (`MN-P` item 2)

extension Frame {
    /// Paints the tooltip after every other paint, the menu panel included, on
    /// a layer above every layer the frame used: a `.surfaceSecondary` panel
    /// with a `.separator` border, radius 4, its 11-pt text inset 6 × 4 and
    /// wrapping at 300 pt. Text goes through `textSystem` (`TS-A`). Nothing
    /// without a tooltip.
    func paintTooltip() {
        guard let tooltip else { return }
        let layer = (scene.highestLayer ?? 0) + 1
        let font = textSystem.resolveFont(TooltipPlacement.fontDescriptor)
        withPaintLayer(layer) {
            fill(tooltip.frame, color: theme[.surfaceSecondary],
                 cornerRadii: Corners(all: Pixels(TooltipPlacement.cornerRadius)),
                 borderColor: theme[.separator], borderWidths: Edges(all: Pixels(1)))
            let origin = (x: Double(tooltip.frame.origin.x.value + TooltipPlacement.paddingX),
                          y: Double(tooltip.frame.origin.y.value + TooltipPlacement.paddingY))
            let glyphs = textSystem.placeGlyphs(tooltip.text, font: font, wrappingAt: TooltipPlacement.wrapWidth,
                                                origin: origin, scaleFactor: scaleFactor)
            for glyph in glyphs { draw(glyph, color: theme[.textPrimary]) }
        }
    }
}
