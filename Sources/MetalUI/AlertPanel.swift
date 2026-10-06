import MetalUICore
import MetalUIPlatform
import MetalUITextSystem

// Platform services, lane 3 — the drawn alert (rulings `SV-J` items 2–4,
// `SV-X`, `SV-AC`, `SV-AK`; spec §4.2's `AlertPanel.swift`). The model is lane
// 2's (`Window.drawnAlert`, `Window.chooseAlertButton(_:)`, `SV-AH` item 5);
// this file lays it out, paints it, takes input while it is up and publishes
// it. Window-owned, as the in-window menu is (`MN-F`): no id in the app's tree,
// no `StateTable` entry, no hitbox. Pure where it can be: `layout` is a
// function of its arguments; `paint` emits through `Frame`'s rect and glyph
// primitives, so no new drawable primitive exists (`TE-AD` not triggered).
// Every look is a constant here.

@MainActor
enum AlertPanel {
    /// The panel's width (a sheet's, `SV-J` item 2).
    static let width: Float = 260
    /// The panel's distance from the window's top edge.
    static let top: Float = 24
    /// The panel's corner radius.
    static let cornerRadius: Float = 10
    /// Inside the panel, on every edge.
    static let padding: Float = 16
    /// Between the title and the message.
    static let messageGap: Float = 6
    /// Above the buttons.
    static let buttonsGap: Float = 16
    /// A button's height.
    static let buttonHeight: Float = 28
    /// Between two buttons, on either axis.
    static let buttonSpacing: Float = 8
    /// A button's corner radius.
    static let buttonRadius: Float = 6
    /// The focus ring's width.
    static let ringWidth: Float = 2
    /// The panel's shadow — the popover chrome's default, as the menu's.
    static let shadowRadius: Float = 8
    static let shadowY: Float = 2

    /// The panel's geometry in window points.
    struct Layout: Equatable {
        var panel: Bounds<Pixels>
        /// Where the title's first line starts.
        var titleOrigin: Point<Pixels>
        /// Where the message's first line starts, if there is one.
        var messageOrigin: Point<Pixels>?
        /// One rect per button, in the resolver's order.
        var buttons: [Bounds<Pixels>]
    }

    /// The title's face: the control font, bold.
    static var titleDescriptor: FontDescriptor {
        resolveTextStyle(TextStyleRequest(weight: .bold), in: EnvironmentValues()).descriptor
    }

    /// The message's and the buttons' face: the control font.
    static var bodyDescriptor: FontDescriptor {
        resolveTextStyle(TextStyleRequest(), in: EnvironmentValues()).descriptor
    }

    /// The text width inside the panel, where the title and message wrap.
    static var textWidth: Float { width - 2 * padding }

    /// The panel for `title`, `message` and `buttonCount` buttons in a window
    /// of `window`: centred horizontally, `top` from the top; the title, the
    /// message `messageGap` below it, then the buttons `buttonsGap` below —
    /// one or two side by side (the resolver's first on the trailing side),
    /// three or more stacked top-down in the resolver's order (`SV-J` item 2).
    static func layout(title: String, message: String?, buttonCount: Int, window: Size<Pixels>,
                       textSystem: any TextSystem) -> Layout {
        let titleFont = textSystem.resolveFont(titleDescriptor)
        let bodyFont = textSystem.resolveFont(bodyDescriptor)
        let originX = ((window.width.value - width) / 2).rounded(.down)
        let x = originX + padding
        var y = top + padding
        let titleOrigin = Point(x: Pixels(x), y: Pixels(y))
        y += Float(textSystem.measure(title, font: titleFont, wrappingAt: Double(textWidth)).totalHeight).rounded(.up)
        var messageOrigin: Point<Pixels>?
        if let message, !message.isEmpty {
            y += messageGap
            messageOrigin = Point(x: Pixels(x), y: Pixels(y))
            y += Float(textSystem.measure(message, font: bodyFont, wrappingAt: Double(textWidth)).totalHeight)
                .rounded(.up)
        }
        y += buttonsGap
        var buttons: [Bounds<Pixels>] = []
        if buttonCount <= 2 {
            let each = buttonCount == 2 ? (textWidth - buttonSpacing) / 2 : textWidth
            for index in 0..<buttonCount {
                // The first is trailing: with two, index 0 is on the right.
                let slot = buttonCount == 2 ? 1 - index : 0
                buttons.append(Bounds(origin: Point(x: Pixels(x + Float(slot) * (each + buttonSpacing)), y: Pixels(y)),
                                      size: Size(width: Pixels(each), height: Pixels(buttonHeight))))
            }
            y += buttonCount > 0 ? buttonHeight : 0
        } else {
            for index in 0..<buttonCount {
                if index > 0 { y += buttonSpacing }
                buttons.append(Bounds(origin: Point(x: Pixels(x), y: Pixels(y)),
                                      size: Size(width: Pixels(textWidth), height: Pixels(buttonHeight))))
                y += buttonHeight
            }
        }
        y += padding
        let panel = Bounds(origin: Point(x: Pixels(originX), y: Pixels(top)),
                           size: Size(width: Pixels(width), height: Pixels(y - top)))
        return Layout(panel: panel, titleOrigin: titleOrigin, messageOrigin: messageOrigin, buttons: buttons)
    }
}

/// What a frame paints for the drawn alert: the model, its layout and the ring.
struct DrawnAlertPanel {
    let alert: DrawnAlert
    let layout: AlertPanel.Layout
    /// The window's content size, which the scrim covers.
    let window: Size<Pixels>
}

// MARK: - Paint (`SV-J` item 2)

extension Frame {
    /// Paints the drawn alert after every other paint — the in-window menu and
    /// the tooltip included — on a layer above every layer the frame used: a
    /// `.scrim` wash over the window, a `.surface` panel with the default
    /// shadow and a `.separator` border, the bold title, the message, and the
    /// buttons — the default one (`SV-X`) `.accent` with `.background` text,
    /// the rest `.surfaceSecondary` with a `.separator` border — and a 2-pt
    /// accent ring around the ringed button. Text goes through `textSystem`
    /// (`TS-A`). Nothing without a drawn alert.
    func paintAlertPanel() {
        guard let drawn = alertPanel else { return }
        let layer = (scene.highestLayer ?? 0) + 1
        let titleFont = textSystem.resolveFont(AlertPanel.titleDescriptor)
        let bodyFont = textSystem.resolveFont(AlertPanel.bodyDescriptor)
        let lineHeight = Float(textSystem.fontMetrics(bodyFont).lineHeight)
        let layout = drawn.layout
        func text(_ string: String, font: FontKey, at origin: Point<Pixels>, wrapping: Double?, color: Hsla) {
            let glyphs = textSystem.placeGlyphs(string, font: font, wrappingAt: wrapping,
                                                origin: (x: Double(origin.x.value), y: Double(origin.y.value)),
                                                scaleFactor: scaleFactor)
            for glyph in glyphs { draw(glyph, color: color) }
        }
        withPaintLayer(layer) {
            fill(Bounds(origin: Point(x: Pixels(0), y: Pixels(0)), size: drawn.window), color: theme[.scrim])
            paintWithShadow(color: theme[.shadow], radius: Pixels(AlertPanel.shadowRadius), x: Pixels(0),
                            y: Pixels(AlertPanel.shadowY)) {
                fill(layout.panel, color: theme[.surface],
                     cornerRadii: Corners(all: Pixels(AlertPanel.cornerRadius)),
                     borderColor: theme[.separator], borderWidths: Edges(all: Pixels(1)))
            }
            text(drawn.alert.title, font: titleFont, at: layout.titleOrigin,
                 wrapping: Double(AlertPanel.textWidth), color: theme[.textPrimary])
            if let message = drawn.alert.message, let origin = layout.messageOrigin {
                text(message, font: bodyFont, at: origin, wrapping: Double(AlertPanel.textWidth),
                     color: theme[.textPrimary])
            }
            for (index, button) in drawn.alert.buttons.enumerated() where layout.buttons.indices.contains(index) {
                let rect = layout.buttons[index]
                let isDefault = button.platform.isDefault
                fill(rect, color: theme[isDefault ? .accent : .surfaceSecondary],
                     cornerRadii: Corners(all: Pixels(AlertPanel.buttonRadius)),
                     borderColor: isDefault ? .transparent : theme[.separator],
                     borderWidths: Edges(all: Pixels(isDefault ? 0 : 1)))
                if drawn.alert.ring == index {
                    let inset = AlertPanel.ringWidth + 1
                    fill(Bounds(origin: Point(x: Pixels(rect.origin.x.value - inset),
                                              y: Pixels(rect.origin.y.value - inset)),
                                size: Size(width: Pixels(rect.size.width.value + 2 * inset),
                                           height: Pixels(rect.size.height.value + 2 * inset))),
                         color: .transparent,
                         cornerRadii: Corners(all: Pixels(AlertPanel.buttonRadius + inset)),
                         borderColor: theme[.accent], borderWidths: Edges(all: Pixels(AlertPanel.ringWidth)))
                }
                let title = button.platform.title
                let width = Float(textSystem.measure(title, font: bodyFont, wrappingAt: nil).widestLine)
                let origin = Point(x: Pixels(rect.origin.x.value + (rect.size.width.value - width) / 2),
                                   y: Pixels(rect.origin.y.value + (rect.size.height.value - lineHeight) / 2))
                text(title, font: bodyFont, at: origin, wrapping: nil,
                     color: theme[isDefault ? .background : .textPrimary])
            }
        }
    }
}

// MARK: - Window: layout, the modal input stage, accessibility (`SV-J` items 3–4)

extension Window {
    /// The drawn alert's panel against the window's current size, or `nil`.
    var drawnAlertPanel: DrawnAlertPanel? {
        guard let alert = drawnAlert else { return nil }
        return DrawnAlertPanel(alert: alert,
                               layout: AlertPanel.layout(title: alert.title, message: alert.message,
                                                         buttonCount: alert.buttons.count,
                                                         window: contentSizeForDrag, textSystem: menuTextSystem),
                               window: contentSizeForDrag)
    }

    /// The drawn alert's modal stage (`SV-J` item 3), first after the pointer
    /// state and the dialog and alert answers: while an alert is drawn it
    /// takes every pointer, wheel and key event, consuming each — Return
    /// presses the default (`SV-X`), Escape the cancel button, Tab and the
    /// arrows move the ring, Space presses the ringed button, a click on a
    /// button presses it; a menu's outcome and the pointer leaving pass, and
    /// a drop from outside is refused. `nil` passes the event on (nothing is
    /// drawn, or the event is not the alert's); otherwise the answer.
    func dispatchDrawnAlert(_ event: InputEvent) -> Bool? {
        guard var alert = drawnAlert else { return nil }
        switch event {
        case .menuAction, .pointerExited, .fileDialogResult, .alertResult:
            return nil
        case .drop:
            return false
        case .mouseUp(let mouse):
            if let panel = drawnAlertPanel,
               let index = panel.layout.buttons.firstIndex(where: { $0.contains(mouse.position) }) {
                chooseAlertButton(index)
            }
            return true
        case .keyDown(let key):
            let buttons = alert.buttons
            switch key.charactersIgnoringModifiers {
            case "\r", "\u{3}":
                if let index = buttons.firstIndex(where: \.platform.isDefault) { chooseAlertButton(index) }
            case "\u{1b}":
                if let index = buttons.firstIndex(where: \.platform.isCancel) { chooseAlertButton(index) }
            case " ":
                if let ring = alert.ring { chooseAlertButton(ring) }
            case "\t", "\u{19}", "\u{f701}", "\u{f700}", "\u{f702}", "\u{f703}":
                guard !buttons.isEmpty else { return true }
                let backward = key.charactersIgnoringModifiers == "\u{19}" || key.modifiers.contains(.shift)
                    || key.charactersIgnoringModifiers == "\u{f700}"
                    || key.charactersIgnoringModifiers == "\u{f702}"
                let count = buttons.count
                if let ring = alert.ring {
                    alert.ring = backward ? (ring + count - 1) % count : (ring + 1) % count
                } else {
                    alert.ring = backward ? count - 1 : 0
                }
                drawnAlert = alert
            default:
                break
            }
            return true
        case .textInput(let text):
            // A focused field beneath turns Space into text: it still presses.
            if text == " ", let ring = alert.ring { chooseAlertButton(ring) }
            return true
        default:
            return true
        }
    }

    /// The window-reserved root every drawn-alert node id descends from —
    /// never written to `StateTable` (`theSevenRetentionSlotsAreMutuallyDistinct`
    /// is unmoved; `MN-F` item 4's footing).
    static let alertPanelRoot = GlobalElementID(component: .named(ElementID("$alert-panel")), parent: nil)

    static func alertPanelButtonID(_ index: Int) -> GlobalElementID {
        GlobalElementID.child(of: alertPanelRoot, at: index, name: nil)
    }

    /// Appends the drawn alert to `build` (`SV-J` item 4): one `.alert` root
    /// (label the title, value the message) whose children are its `.button`
    /// nodes, focus on the ringed one — after the content's roots and the
    /// in-window menu's, so it is published under modal isolation too.
    func appendAlertPanel(to build: inout AccessibilityBuild) {
        guard let panel = drawnAlertPanel else { return }
        var tree = build.tree
        let rootID = AccessibilityNodeID(Self.alertPanelRoot)
        var children: [AccessibilityNodeID] = []
        for (index, button) in panel.alert.buttons.enumerated() where panel.layout.buttons.indices.contains(index) {
            let id = AccessibilityNodeID(Self.alertPanelButtonID(index))
            children.append(id)
            tree.nodes[id] = AccessibilityNode(role: .button, label: button.platform.title, actions: .press)
            let frame = panel.layout.buttons[index]
            tree.geometry[id] = AccessibilityGeometry(frame: frame, visibleFrame: frame, layer: Int.max, order: Int.max)
        }
        tree.nodes[rootID] = AccessibilityNode(role: .alert, label: panel.alert.title, value: panel.alert.message,
                                               children: children)
        tree.geometry[rootID] = AccessibilityGeometry(frame: panel.layout.panel, visibleFrame: panel.layout.panel,
                                                      layer: Int.max, order: Int.max)
        tree.roots.append(rootID)
        tree.focused = panel.alert.ring.map { AccessibilityNodeID(Self.alertPanelButtonID($0)) } ?? rootID
        build.tree = tree
    }

    /// An accessibility press while an alert is drawn (`SV-J` items 3–4): on
    /// one of its buttons, chooses it; on anything else, refused — the alert
    /// is modal. `nil` when no alert is drawn.
    func pressAlertButton(_ id: GlobalElementID) -> Bool? {
        guard let alert = drawnAlert else { return nil }
        guard id.parent == Self.alertPanelRoot, case .positional(let index) = id.component,
              alert.buttons.indices.contains(index) else { return false }
        chooseAlertButton(index)
        setNeedsRedraw()
        return true
    }
}
