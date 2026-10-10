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
    /// The band at a scrolling level's edge past which more rows lie, showing
    /// `▴` or `▾` (`SV-Q`).
    nonisolated static let indicatorHeight: Float = 12

    /// The height a level of `size` is clamped to in `window` — the window
    /// less a `margin` above and below — or `nil` when it fits (`SV-Q`).
    static func clampedHeight(_ size: Size<Pixels>, in window: Size<Pixels>) -> Float? {
        let available = max(window.height.value - 2 * margin, 0)
        return size.height.value > available ? available : nil
    }

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

    /// What the drawn menu calls the `.command` modifier off Apple — the key
    /// the SDL bridge maps `SDL_KMOD_GUI` to (ruling `SG-B` item 5): "Win" on
    /// Windows, "Super" elsewhere.
    static var superKeyName: String {
        #if os(Windows)
        return "Win"
        #else
        return "Super"
        #endif
    }

    /// A shortcut as shown: `⌃⌥⇧⌘K` on Apple; elsewhere each held key by its
    /// own name, `Ctrl+Super+Alt+Shift+K` (ruling `SG-B` item 5) — `.command`
    /// is `superKeyName`, never "Ctrl", so a default (`.primary`, Ctrl off
    /// Apple) shortcut reads `Ctrl+S` and is Ctrl+S.
    static func shortcutText(_ shortcut: PlatformKeyEquivalent?, platform: TextEditing.Platform,
                             superKeyName: String = MenuPanel.superKeyName) -> String? {
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
            if shortcut.modifiers.contains(.control) { parts.append("Ctrl") }
            if shortcut.modifiers.contains(.command) { parts.append(superKeyName) }
            if shortcut.modifiers.contains(.option) { parts.append("Alt") }
            if shortcut.modifiers.contains(.shift) { parts.append("Shift") }
            return (parts + [key]).joined(separator: "+")
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

// MARK: - Paint (`MN-F` item 2)

extension Frame {
    /// Paints the open in-window menu after every other paint, the drag
    /// preview included, on a layer above every layer the frame used: per
    /// level a `.surface` panel with a `.separator` border and the default
    /// shadow; the highlighted row in `.accent` with `.background` text; a
    /// `✓` for an on item, the title, the shortcut right-aligned, `▸` on a
    /// submenu row, a hairline for a separator; disabled rows at half opacity.
    /// Text goes through `textSystem` (`TS-A`). Nothing without a menu.
    func paintMenuPanel() {
        guard !menuPanelLevels.isEmpty else { return }
        let layer = (scene.highestLayer ?? 0) + 1
        let font = textSystem.resolveFont(MenuPanel.fontDescriptor)
        let lineHeight = Float(textSystem.fontMetrics(font).lineHeight)
        withPaintLayer(layer) {
            for level in menuPanelLevels {
                paintWithShadow(color: theme[.shadow], radius: Pixels(MenuPanel.shadowRadius), x: Pixels(0),
                                y: Pixels(MenuPanel.shadowY)) {
                    fill(level.frame, color: theme[.surface],
                         cornerRadii: Corners(all: Pixels(MenuPanel.cornerRadius)),
                         borderColor: theme[.separator], borderWidths: Edges(all: Pixels(1)))
                }
                // Only the rows meeting the visible band, clipped to it
                // (`SV-Q`: paint is O(visible)).
                let band = level.visibleBand
                pushClip(band, offset: Point(x: Pixels(0), y: Pixels(0)))
                for index in level.visibleRows {
                    paintMenuRow(level, index, font: font, lineHeight: lineHeight)
                    menuRowsPainted += 1
                }
                popClip()
                paintScrollIndicators(level, font: font, lineHeight: lineHeight)
            }
        }
    }

    /// `▴` centred in the top band while rows lie above, `▾` in the bottom
    /// band while rows lie below (`SV-Q`).
    private func paintScrollIndicators(_ level: MenuSession.Level, font: FontKey, lineHeight: Float) {
        guard level.isScrollable else { return }
        let panel = level.frame
        func arrow(_ string: String, bandTop: Float) {
            let width = Float(textSystem.measure(string, font: font, wrappingAt: nil).widestLine)
            let origin = (x: Double(panel.origin.x.value + (panel.size.width.value - width) / 2),
                          y: Double(bandTop + (MenuPanel.indicatorHeight - lineHeight) / 2))
            for glyph in textSystem.placeGlyphs(string, font: font, wrappingAt: nil, origin: origin,
                                                scaleFactor: scaleFactor) {
                draw(glyph, color: theme[.textPrimary])
            }
        }
        if level.scrollOffset > 0 { arrow("▴", bandTop: panel.origin.y.value) }
        if level.scrollOffset < level.maxScrollOffset {
            arrow("▾", bandTop: panel.origin.y.value + panel.size.height.value - MenuPanel.indicatorHeight)
        }
    }

    private func paintMenuRow(_ level: MenuSession.Level, _ index: Int, font: FontKey, lineHeight: Float) {
        let item = level.items[index]
        let row = level.rowFrame(index)
        if case .separator = item.kind {
            let y = row.origin.y.value + row.size.height.value / 2
            fill(Bounds(origin: Point(x: Pixels(row.origin.x.value + 6), y: Pixels(y)),
                        size: Size(width: Pixels(row.size.width.value - 12), height: Pixels(1))),
                 color: theme[.separator])
            return
        }
        let highlighted = level.highlighted == index
        if highlighted {
            fill(Bounds(origin: Point(x: Pixels(row.origin.x.value + 4), y: row.origin.y),
                        size: Size(width: Pixels(row.size.width.value - 8), height: row.size.height)),
                 color: theme[.accent], cornerRadii: Corners(all: Pixels(4)))
        }
        let color = theme[highlighted ? .background : .textPrimary]
        let top = Double(row.origin.y.value + (row.size.height.value - lineHeight) / 2)
        func text(_ string: String, x: Float) {
            let glyphs = textSystem.placeGlyphs(string, font: font, wrappingAt: nil,
                                                origin: (x: Double(x), y: top), scaleFactor: scaleFactor)
            for glyph in glyphs { draw(glyph, color: color) }
        }
        func width(_ string: String) -> Float { Float(textSystem.measure(string, font: font, wrappingAt: nil).widestLine) }
        if !item.isEnabled { pushOpacity(MenuPanel.disabledOpacity) }
        if item.isOn { text("✓", x: row.origin.x.value + 6) }
        text(item.title, x: row.origin.x.value + MenuPanel.checkColumn)
        let trailing = row.origin.x.value + row.size.width.value
        if case .submenu = item.kind {
            text("▸", x: trailing - MenuPanel.arrowColumn + 4)
        } else if let shortcut = MenuPanel.shortcutText(item.shortcut, platform: TextEditing.platform) {
            text(shortcut, x: trailing - MenuPanel.trailingPadding - width(shortcut))
        }
        if !item.isEnabled { popOpacity() }
    }
}
