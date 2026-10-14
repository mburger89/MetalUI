import MetalUICore
import MetalUILayout
import MetalUIPlatform

// SDL custom chrome, lane 1 — the drawn window buttons (rulings `CW-C`, `CW-D`, `CW-M` 3 and 4; spec
// `docs/superpowers/specs/2026-10-13-sdl-chrome-design.md` "Mechanism" 4). Where the platform has no native
// window buttons under the hidden title-bar style (`PlatformWindow.hasNativeWindowControls == false`: SDL)
// the window draws three — minimise, zoom, close — in a cluster across the top corner, laid out in their own
// run under the named root `$windowcontrols` (the `$menubar`/`$toolbar` precedent: an element name, not a
// `StateTable` slot; `CW-Q` records why this is a named root and not a `Deferred`). The buttons are ordinary
// `Button`s: their hitboxes are opaque, so they are blockers of the drag regions like any, and close goes
// through `performClose()` — the `AS-B` veto. The strip is **not** an open presentation (`CW-M` 3) and its
// buttons sit last in Tab order (`CW-M` 4: prepainted after the root, the toolbar strip and the menu bar).

/// What a build needs to draw the window buttons: which corner, how tall, the zoom state and the three
/// actions. Handed to `Frame` by `Window`; the actions hold the window weakly.
struct WindowControlsSpec {
    /// Whether the cluster is at the right (Windows, Linux) rather than the left (macOS through SDL).
    let onRight: Bool
    /// The band's height: the strip's.
    let bandHeight: Float
    /// Whether the window is zoomed: the zoom button reads "Restore".
    let isZoomed: Bool
    let minimize: @MainActor () -> Void
    let toggleZoom: @MainActor () -> Void
    let close: @MainActor () -> Void
}

@MainActor
enum WindowControlsStrip {
    /// One button of the right-hand cluster: 46 x 32 (`CW-C`).
    static let buttonWidth: Float = 46
    /// The right-hand cluster's width: three buttons, 138 (`CW-D`).
    static let rightWidth: Float = 138
    /// The left-hand cluster's width, macOS through SDL: AppKit's 70-point reach (`CW-D`).
    static let leftWidth: Float = 70
    /// The macOS-style circle's diameter.
    static let circle: Float = 12
    /// The strip's root: a window-owned **named** root, `$windowcontrols`, at cursor index 3 beside the
    /// window root's `(nil, 0)`, `$toolbar`'s 1 and `$menubar`'s 2.
    static let rootID = GlobalElementID.child(of: nil, at: rootIndex, name: ElementID("$windowcontrols"))
    /// The cursor index `rootID` is noted at.
    static let rootIndex = 3

    /// The cluster's rect in a window `width` points wide.
    static func rect(for spec: WindowControlsSpec, windowWidth: Float) -> LayoutRect {
        let clusterWidth = Double(spec.onRight ? rightWidth : leftWidth)
        return LayoutRect(x: spec.onRight ? Double(windowWidth) - clusterWidth : 0, y: 0,
                          width: clusterWidth, height: Double(spec.bandHeight))
    }

    /// The accessibility label and glyph of the zoom button.
    private static func zoomLabel(_ isZoomed: Bool) -> String { isZoomed ? "Restore" : "Zoom" }

    /// The cluster: three plain buttons in an `HStack(spacing: 0)`. Right-hand: flat 46-wide rectangles
    /// filled `.surface`, minimise, zoom, close. Left-hand: three 12-point circles in AppKit's order (close,
    /// minimise, zoom) padded 8.
    static func element(_ spec: WindowControlsSpec) -> AnyElement {
        let zoomName = zoomLabel(spec.isZoomed)
        if spec.onRight {
            return AnyElement(
                HStack(spacing: Pixels(0)) {
                    flat("–", "Minimise", spec, spec.minimize)
                    flat(spec.isZoomed ? "◱" : "□", zoomName, spec, spec.toggleZoom)
                    flat("×", "Close", spec, spec.close)
                })
        }
        return AnyElement(
            HStack(spacing: Pixels(8)) {
                round(Color(red: 1.0, green: 0.373, blue: 0.341), "Close", spec.close)
                round(Color(red: 0.996, green: 0.737, blue: 0.180), "Minimise", spec.minimize)
                round(Color(red: 0.157, green: 0.784, blue: 0.251), zoomName, spec.toggleZoom)
            }
            .padding(Edges(top: Pixels(0), right: Pixels(0), bottom: Pixels(0), left: Pixels(8))))
    }

    /// A flat button: its glyph centred in 46 x `bandHeight`, `.surface` behind it.
    private static func flat(_ glyph: String, _ name: String, _ spec: WindowControlsSpec,
                             _ action: @escaping @MainActor () -> Void) -> some ElementGroup {
        Button(action: action) {
            Text(glyph).font(size: 13).foregroundColor(.textPrimary)
                .frame(width: Pixels(buttonWidth), height: Pixels(spec.bandHeight))
                .background(.surface)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }

    /// A round button: a coloured 12-point circle.
    private static func round(_ color: Color, _ name: String,
                              _ action: @escaping @MainActor () -> Void) -> some ElementGroup {
        Button(action: action) {
            Circle().fill(color).frame(width: Pixels(circle), height: Pixels(circle))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }
}

extension Frame {
    /// Lays out the window buttons for this build, when the window draws them (`CW-C`): the cluster's
    /// element, requested under `WindowControlsStrip.rootID` after the menu bar, its name noted (`ID-R`).
    /// `nil` otherwise — the window's strip-less path, unchanged.
    func requestWindowControls(pass: inout LayoutPass) -> (element: AnyElement, node: LayoutNodeID)? {
        guard let spec = windowControls else { return nil }
        var element = WindowControlsStrip.element(spec)
        stateTable.noteNamed(WindowControlsStrip.rootID, at: WindowControlsStrip.rootIndex)
        let node = element.requestLayout(WindowControlsStrip.rootID, pass: &pass)
        return (element, node)
    }
}
