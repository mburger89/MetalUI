import MetalUICore
import MetalUIPlatform
import MetalUITextSystem

// Menus, popovers and tooltips, lane 1 — the in-window menu's geometry and
// paint (ruling `MN-F` items 1–2; spec §3.3). Pure where it can be: `layout`
// and the two placements are functions of their arguments, unit-tested; `paint`
// emits through `Frame`'s own rect and glyph primitives, so no new drawable
// primitive exists (`TE-AD` is not triggered). Every look is a constant here.

@MainActor
enum MenuPanel {
    /// An item row's height.
    static let rowHeight: Float = 22
    /// A separator row's height.
    static let separatorHeight: Float = 9
    /// Above the first row and below the last.
    static let verticalPadding: Float = 4
    /// The check column at a row's leading edge (`✓`).
    static let checkColumn: Float = 20
    /// The submenu arrow's column at a row's trailing edge (`▸`).
    static let arrowColumn: Float = 18
    /// Between the title and a shortcut.
    static let shortcutGap: Float = 24
    /// After the title (or the shortcut) when there is no arrow.
    static let trailingPadding: Float = 12
    /// No panel is narrower.
    static let minimumWidth: Float = 120
    /// The panel's corner radius.
    static let cornerRadius: Float = 6
    /// The margin a panel keeps from the window's edges (`MN-F` item 1).
    static let margin: Float = 4
    /// The panel's shadow — the popover chrome's default.
    static let shadowRadius: Float = 8
    static let shadowY: Float = 2
    /// A disabled row's opacity.
    static let disabledOpacity: Float = 0.5

    /// One panel's geometry: row rects relative to the panel's origin, and the
    /// panel's size.
    struct Layout: Equatable {
        var rows: [Bounds<Pixels>]
        var size: Size<Pixels>
    }

    /// The default control font's descriptor, for every panel.
    static var fontDescriptor: FontDescriptor {
        resolveTextStyle(TextStyleRequest(), in: EnvironmentValues()).descriptor
    }

    /// A shortcut as shown: `⌘K` on Apple, `Ctrl+K` elsewhere.
    static func shortcutText(_ shortcut: PlatformKeyEquivalent?, platform: TextEditing.Platform) -> String? {
        guard let shortcut else { return nil }
        let key = shortcut.key.uppercased()
        switch platform {
        case .mac:
            var s = ""
            if shortcut.modifiers.contains(.control) { s += "⌃" }
            if shortcut.modifiers.contains(.option) { s += "⌥" }
            if shortcut.modifiers.contains(.shift) { s += "⇧" }
            if shortcut.modifiers.contains(.command) { s += "⌘" }
            return s + key
        case .other:
            var parts: [String] = []
            if shortcut.modifiers.contains(.command) { parts.append("Ctrl") }
            if shortcut.modifiers.contains(.control) { parts.append("Ctrl") }
            if shortcut.modifiers.contains(.option) { parts.append("Alt") }
            if shortcut.modifiers.contains(.shift) { parts.append("Shift") }
            var seen = Set<String>()
            return (parts.filter { seen.insert($0).inserted } + [key]).joined(separator: "+")
        }
    }

    /// The rows and size of a panel showing `items`: 22-pt item rows, 9-pt
    /// separators, 4 pt above and below; as wide as its widest row's check
    /// column, title, shortcut and arrow, at least `minimumWidth`.
    static func layout(items: [PlatformMenuItem], textSystem: any TextSystem, font: FontKey,
                       platform: TextEditing.Platform = TextEditing.platform) -> Layout {
        var width = minimumWidth
        var y = verticalPadding
        var rows: [Bounds<Pixels>] = []
        rows.reserveCapacity(items.count)
        let hasSubmenu = items.contains { if case .submenu = $0.kind { true } else { false } }
        for item in items {
            let height: Float
            if case .separator = item.kind {
                height = separatorHeight
            } else {
                height = rowHeight
                var w = checkColumn + Float(textSystem.measure(item.title, font: font, wrappingAt: nil).widestLine)
                if let shortcut = shortcutText(item.shortcut, platform: platform) {
                    w += shortcutGap + Float(textSystem.measure(shortcut, font: font, wrappingAt: nil).widestLine)
                }
                w += hasSubmenu ? arrowColumn : trailingPadding
                width = max(width, w.rounded(.up))
            }
            rows.append(Bounds(origin: Point(x: Pixels(0), y: Pixels(y)),
                               size: Size(width: Pixels(0), height: Pixels(height))))
            y += height
        }
        for index in rows.indices { rows[index].size.width = Pixels(width) }
        return Layout(rows: rows, size: Size(width: Pixels(width), height: Pixels(y + verticalPadding)))
    }

    /// A root panel's origin for a press at `point` (`MN-F` item 1): its
    /// top-left corner at the point, flipped left or up on an axis where it
    /// would leave the window, then clamped inside it with `margin`.
    static func place(size: Size<Pixels>, at point: Point<Pixels>, in window: Size<Pixels>) -> Point<Pixels> {
        Point(x: Pixels(placeAxis(start: point.x.value, flippedEnd: point.x.value, extent: size.width.value,
                                  window: window.width.value)),
              y: Pixels(placeAxis(start: point.y.value, flippedEnd: point.y.value, extent: size.height.value,
                                  window: window.height.value)))
    }

    /// A submenu's origin beside its row (`MN-F` item 1): to the right of its
    /// parent panel, flipped to the left where it would leave the window, its
    /// first row top-aligned with the row, then clamped inside the window.
    static func placeSubmenu(size: Size<Pixels>, row: Bounds<Pixels>, parent: Bounds<Pixels>,
                             in window: Size<Pixels>) -> Point<Pixels> {
        let x = placeAxis(start: parent.origin.x.value + parent.size.width.value,
                          flippedEnd: parent.origin.x.value, extent: size.width.value,
                          window: window.width.value)
        let top = row.origin.y.value - verticalPadding
        let y = clamp(top, extent: size.height.value, window: window.height.value)
        return Point(x: Pixels(x), y: Pixels(y))
    }

    /// Starts at `start`; if `start + extent` passes the far margin, ends at
    /// `flippedEnd` instead; then clamps.
    private static func placeAxis(start: Float, flippedEnd: Float, extent: Float, window: Float) -> Float {
        let value = start + extent > window - margin ? flippedEnd - extent : start
        return clamp(value, extent: extent, window: window)
    }

    private static func clamp(_ value: Float, extent: Float, window: Float) -> Float {
        max(margin, min(value, window - margin - extent))
    }
}
