import MetalUICore
import MetalUILayout
import MetalUIPlatform

// Port gaps (medium), lane 3 — the drawn toolbar strip (rulings `MD-K`,
// `MD-Z`; spec `docs/superpowers/specs/2026-10-07-port-gaps-medium-design.md`
// §3.3 item 4). Where the platform declines a toolbar (`setToolbar` answers
// `false`: SDL), the window draws it: a 39-point strip across its top, the
// declared controls themselves laid out in their own run under the named root
// `$toolbar`, the root laid out in the rect below. Divergence 136: AppKit
// grows the window by its toolbar; the strip takes the content's height.

/// One toolbar control as the strip shows it: the id the platform item has
/// (`MD-I` item 6), its placement, whether it is enabled, and the declared
/// control.
struct ToolbarStripItem {
    let id: String
    let placement: PlatformToolbarPlacement
    let isEnabled: Bool
    let element: @MainActor () -> AnyElement

    /// The control under `.disabled(_:)` when its item is disabled (the
    /// scope's `isEnabled` and the item's own, `MD-I` item 3) — the strip is
    /// laid out under the window's root environment, not the declaring
    /// scope's (`MD-Z` item 3).
    @MainActor func body() -> EnvironmentScope<AnyElement> {
        element().disabled(!isEnabled)
    }
}

/// The drawn strip's geometry and element (`MD-K` items 1–3).
@MainActor
enum ToolbarStrip {
    /// The strip's height: 7 + the regular control height 24 + 7, and the
    /// 1-point separator below (`MD-K` item 1).
    /// Public as `Window.drawnChromeHeight` (ruling `SG-F` item 4).
    static let height: Float = 39
    /// The bar above the separator.
    static let barHeight: Float = 38
    /// The width of `.searchable`'s field in the strip.
    static let searchWidth: Float = 160
    /// The strip's root: a window-owned **named** root, `$toolbar` — an
    /// element name, not a `StateTable` slot (the seven retention slots are
    /// unmoved). Its position is `(nil, 1)`, beside the window root's
    /// `(nil, 0)`, so it never replaces the root's name (`ID-R`).
    static let rootID = GlobalElementID.child(of: nil, at: rootIndex, name: ElementID("$toolbar"))
    /// The cursor index `rootID` is noted at.
    static let rootIndex = 1

    /// The strip for `items` across a window `width` wide: navigation items
    /// leading, a `Spacer`, then the primary-action and automatic items and
    /// the search fields trailing, in an `HStack(spacing: 8)` padded 8
    /// horizontally; principal and status items centred in an overlay; a
    /// 1-point `.separator` line below; filled `.surface`. Each item is keyed
    /// by its platform id (`ForEach(id:)`), so an item keeps its state while
    /// its id does and a returning id starts fresh (`ID-R`, `DD-C`; test 3.9).
    static func element(items: [ToolbarStripItem], width: Float) -> AnyElement {
        let leading = items.filter { $0.placement == .navigation }
        let centre = items.filter { $0.placement == .principal || $0.placement == .status }
        let trailing = items.filter {
            $0.placement == .primaryAction || $0.placement == .automatic || $0.placement == .search
        }
        return AnyElement(
            VStack(spacing: Pixels(0)) {
                HStack(spacing: Pixels(8)) {
                    ForEach(leading, id: \.id) { item in item.body() }
                    Spacer()
                    ForEach(trailing, id: \.id) { item in item.body() }
                }
                .padding(Edges(top: Pixels(0), right: Pixels(8), bottom: Pixels(0), left: Pixels(8)))
                .frame(width: Pixels(width), height: Pixels(barHeight))
                .overlay {
                    HStack(spacing: Pixels(8)) {
                        ForEach(centre, id: \.id) { item in item.body() }
                    }
                }
                Color(.separator).frame(width: Pixels(width), height: Pixels(1))
            }
            .background(.surface))
    }
}

extension Frame {
    /// Lays out the drawn strip for this build's toolbar, when the window
    /// draws one and the build declared an item (`MD-K`): the strip's
    /// element, requested under `ToolbarStrip.rootID` after the root's
    /// layout (the toolbar records are complete then), its name noted
    /// (`ID-R`). `nil` otherwise — the window's strip-less path, unchanged.
    func requestToolbarStrip(pass: inout LayoutPass) -> (element: AnyElement, node: LayoutNodeID)? {
        guard drawsToolbarStrip else { return nil }
        let items = AssembledToolbar(records: toolbarRecords).strip
        guard !items.isEmpty else { return nil }
        var element = ToolbarStrip.element(items: items, width: contentSize.width.value)
        stateTable.noteNamed(ToolbarStrip.rootID, at: ToolbarStrip.rootIndex)
        let node = element.requestLayout(ToolbarStrip.rootID, pass: &pass)
        return (element, node)
    }
}
