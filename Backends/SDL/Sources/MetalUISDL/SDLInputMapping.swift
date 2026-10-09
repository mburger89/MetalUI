// Compiled only under the `SDL` trait (ruling PX-H item 2).
#if SDL
import MetalUIPlatform
import SDLBridge

/// SDL's mouse buttons in AppKit's numbering (ruling `CI-E` item 4), the one
/// `MouseEvent.buttonNumber` uses.
enum SDLButtons {
    /// AppKit's number for SDL button `sdlButton`: left 0, right 1, middle 2,
    /// X1 (back) 3, X2 (forward) 4, and each further button one below its SDL
    /// number. Compared against the C-exported `mui_sdl_button_*` constants,
    /// never an SDL value spelled in Swift.
    static func appKitNumber(sdlButton: Int32) -> Int {
        if sdlButton == Int32(mui_sdl_button_left) { return 0 }
        if sdlButton == Int32(mui_sdl_button_right) { return 1 }
        if sdlButton == Int32(mui_sdl_button_middle) { return 2 }
        if sdlButton == Int32(mui_sdl_button_x1) { return 3 }
        if sdlButton == Int32(mui_sdl_button_x2) { return 4 }
        return Int(sdlButton) - 1
    }
}

/// A trackpad pinch on SDL (ruling `CI-K` items 1 and 2), as pure rules.
enum SDLPinch {
    /// Whether the video driver `driver` sends a pinch's **cumulative** scale
    /// (since the gesture began) rather than a per-event ratio. Read in SDL
    /// 3.4.16's source, not measured on hardware: `cocoa` sends
    /// `1 + magnification` per event; `x11` and `wayland` the protocol's
    /// cumulative scale; every other driver, the offscreen one included, is
    /// taken as cumulative (`CI-K` item 1's cost line says what a wrong reading
    /// does — human check Y7).
    static func isCumulative(driver: String) -> Bool { driver != "cocoa" }

    /// This event's additive magnification delta: on a cumulative driver the
    /// scale less the previous event's (1 at the gesture's start); on a ratio
    /// driver the scale less 1.
    static func delta(scale: Double, previous: Double, cumulative: Bool) -> Double {
        cumulative ? scale - previous : scale - 1
    }

    /// The window a pinch goes to: the one SDL names; with window id 0 (cocoa
    /// sends none) the window with mouse focus, else the keyboard-focused
    /// window, else none (each 0 for "none").
    static func route(windowID: UInt32, mouseFocus: UInt32, keyboardFocus: UInt32) -> UInt32? {
        if windowID != 0 { return windowID }
        if mouseFocus != 0 { return mouseFocus }
        if keyboardFocus != 0 { return keyboardFocus }
        return nil
    }
}

/// The SDL system cursors MetalUI uses (ruling `CI-H` item 8), by MetalUI's
/// own names; the bridge maps each to its `SDL_SystemCursor`.
enum SDLSystemCursor: Sendable, Hashable {
    case `default`, text, crosshair, move, pointer, ewResize, nsResize
    case nResize, sResize, eResize, wResize, neResize, nwResize, seResize, swResize

    /// The bridge's `MUI_CURSOR_*` for this cursor, converted explicitly (a C
    /// enum constant's type differs between Windows and Apple).
    var bridgeValue: Int32 {
        switch self {
        case .default: Int32(MUI_CURSOR_DEFAULT)
        case .text: Int32(MUI_CURSOR_TEXT)
        case .crosshair: Int32(MUI_CURSOR_CROSSHAIR)
        case .move: Int32(MUI_CURSOR_MOVE)
        case .pointer: Int32(MUI_CURSOR_POINTER)
        case .ewResize: Int32(MUI_CURSOR_EW_RESIZE)
        case .nsResize: Int32(MUI_CURSOR_NS_RESIZE)
        case .nResize: Int32(MUI_CURSOR_N_RESIZE)
        case .sResize: Int32(MUI_CURSOR_S_RESIZE)
        case .eResize: Int32(MUI_CURSOR_E_RESIZE)
        case .wResize: Int32(MUI_CURSOR_W_RESIZE)
        case .neResize: Int32(MUI_CURSOR_NE_RESIZE)
        case .nwResize: Int32(MUI_CURSOR_NW_RESIZE)
        case .seResize: Int32(MUI_CURSOR_SE_RESIZE)
        case .swResize: Int32(MUI_CURSOR_SW_RESIZE)
        }
    }
}

/// The seam's pointer styles as SDL system cursors (ruling `CI-H` item 8).
enum SDLCursorTable {
    /// The system cursor for `style`. **Both grab hands are `move` and both
    /// zooms `default`**: SDL has no hand or zoom cursor — a documented
    /// platform constraint (human check Y6), not a silent approximation. A
    /// frame edge is its own one-edge resize cursor whatever its directions.
    static func systemCursor(for style: PlatformPointerStyle) -> SDLSystemCursor {
        switch style {
        case .arrow, .zoomIn, .zoomOut: .default
        case .iBeam, .verticalIBeam: .text
        case .crosshair: .crosshair
        case .openHand, .closedHand: .move
        case .pointingHand: .pointer
        case .columnResize: .ewResize
        case .rowResize: .nsResize
        case .frameResize(let edge, _, _):
            switch edge {
            case .top: .nResize
            case .bottom: .sResize
            case .leading: .wResize
            case .trailing: .eResize
            case .topLeading: .nwResize
            case .topTrailing: .neResize
            case .bottomLeading: .swResize
            case .bottomTrailing: .seResize
            }
        }
    }
}
#endif
