import MetalUICore
import MetalUIScene

/// One native window as `Window` drives it: size, scale, renderer, display
/// link, input and accessibility callbacks. Its control-state and Reduce Motion
/// pairs have no default implementation, so a conformer that forgets one does
/// not compile (`EV-AB`, `AN-AD`). Conformers: `AppKitWindow` and
/// `Backends/SDL`'s `SDLWindow`.
@MainActor
public protocol PlatformWindow: AnyObject {
    var contentSize: Size<Pixels> { get }
    var scaleFactor: Float { get }
    /// Draws this window's frames (ruling RS-A): the Metal renderer on
    /// AppKit, SDL GPU through `Backends/SDL`.
    var renderer: any WindowRenderer { get }
    var title: String { get set }

    /// The host's current colour environment (spec §7.9). Read at window
    /// construction and re-read on every `onAppearanceChange`.
    var appearance: Appearance { get }

    var onInput: ((InputEvent) -> Bool)? { get set }
    var onResize: ((Size<Pixels>, Float) -> Void)? { get set }
    /// Fired when the host switches between light and dark (spec §7.9:
    /// "`NSApp.effectiveAppearance` / `traitCollectionDidChange` swap the active
    /// theme and mark §4.4's dirty flag").
    ///
    /// A callback carrying the new value rather than a bare "something changed":
    /// the `appearance` getter is a live read of AppKit state, and AppKit
    /// delivers the change notification *while* the effective appearance is
    /// already the new one, so the two agree — but only a passed value makes
    /// that agreement the platform's obligation rather than the caller's
    /// assumption.
    var onAppearanceChange: ((Appearance) -> Void)? { get set }

    /// The window's key state (ruling EV-AB): `.key` while it receives
    /// keyboard input, `.active` while its application (on SDL: another of the
    /// platform's windows) does, `.inactive` otherwise. Read at window
    /// construction and re-read on every `onControlActiveStateChange`; `Window`
    /// stamps it over its root environment's `controlActiveState`.
    ///
    /// **No default implementation, for either requirement** (EV-AB, AB-R's
    /// reason): a conformer that forgets one fails to compile rather than
    /// compiling into a window whose controls never learn it lost key. Pinned
    /// by `aPlatformWindowWithoutTheControlActiveStatePairDoesNotCompile`.
    var controlActiveState: ControlActiveState { get }
    /// Fired with the new value when the key state changes — a passed value,
    /// for `onAppearanceChange`'s reason.
    var onControlActiveStateChange: ((ControlActiveState) -> Void)? { get set }

    /// Whether the user asked the system to reduce motion (plan task 13,
    /// ruling `AN-AD`). Read at window construction and re-read on every
    /// `onAccessibilityReduceMotionChange`; `Window` stamps it over its root
    /// environment's `accessibilityReduceMotion`. AppKit reads
    /// `NSWorkspace.accessibilityDisplayShouldReduceMotion`, as SwiftUI does;
    /// SDL answers `false` (SDL3 has no query).
    ///
    /// **No default implementation, for either requirement** (`EV-AB`'s
    /// reason): a conformer that forgets one fails to compile rather than
    /// compiling into a window that never learns the setting. Pinned by
    /// `aPlatformWindowWithoutTheReduceMotionPairDoesNotCompile`. **Migration**
    /// (`AN-AH` item 7): a conformer outside this repository adds
    /// `var accessibilityReduceMotion: Bool { false }` and
    /// `var onAccessibilityReduceMotionChange: ((Bool) -> Void)?`.
    var accessibilityReduceMotion: Bool { get }
    /// Fired with the new value when the setting changes — a passed value, for
    /// `onAppearanceChange`'s reason.
    var onAccessibilityReduceMotionChange: ((Bool) -> Void)? { get set }

    var onClose: (() -> Void)? { get set }

    /// Fired by the platform when an accessibility client asks for something
    /// (`AccessibilityTree.swift`, ruling AB-A). Answers whether it was handled.
    ///
    /// **No default implementation, for either requirement** (AB-R): a
    /// conformer that forgets one fails to compile rather than compiling into a
    /// window a screen reader cannot see.
    var onAccessibilityRequest: ((AccessibilityRequest) -> Bool)? { get set }
    /// Replaces the tree the platform exposes. Called only after `.activate`,
    /// and only when the tree differs from the last one published (AB-M).
    func publishAccessibilityTree(_ tree: AccessibilityTree)

    /// Begin delivering frame ticks. The callback runs on the main actor and
    /// receives the display link's timestamp in seconds.
    ///
    /// **The timestamp is the link's, not a wall-clock read.** Every element in
    /// one frame must see the same instant, and `CACurrentMediaTime()` sampled
    /// per element would not give them one.
    /// Starts or keeps text input with the caret at `caret` (window points),
    /// where an input method puts its candidate window; `nil` stops it
    /// (ruling TI-A). While it is active a printable key arrives as
    /// `.textInput`, not `.keyDown`. No default implementation, on purpose.
    func setTextInputArea(_ caret: Bounds<Pixels>?)

    /// The system clipboard's plain text, if it holds any (ruling TI-A).
    func readClipboard() -> String?

    /// Replaces the system clipboard's contents with `text`.
    func writeClipboard(_ text: String)

    func startDisplayLink(_ tick: @escaping (Double) -> Void)

    /// Hands an in-window drag to the operating system when the pointer leaves
    /// the window (ruling `DN-K`): the platform starts its own drag session
    /// carrying `representations`, from `position` (window points). Answers
    /// `false` when it cannot — SDL3 has no API to start one (`DN-K` item 4) —
    /// and the drag then stays in the window.
    ///
    /// **No default implementation** (ruling `DN-C` item 2, `EV-AB`'s reason):
    /// a conformer that forgets it fails to compile rather than silently
    /// keeping every drag in the window. Pinned by
    /// `aPlatformWindowWithoutBeginExternalDragDoesNotCompile`. **Migration**
    /// (`DN-C` item 3): a conformer outside this repository adds
    /// `func beginExternalDrag(_: [DragRepresentation], at: Point<Pixels>) -> Bool { false }`.
    func beginExternalDrag(_ representations: [DragRepresentation], at position: Point<Pixels>) -> Bool
    /// Pausing lets an idle window permit display downclocking (spec 4.4).
    func setDisplayLinkPaused(_ paused: Bool)
}

/// A windowing platform: opens windows and runs the event loop. Conformers:
/// `AppKitPlatform` and `Backends/SDL`'s `SDLPlatform` (`XP-B`).
@MainActor
public protocol Platform: AnyObject {
    func openWindow(title: String, size: Size<Pixels>) throws -> any PlatformWindow
    func run()

    /// Shows `images` as the application's icon (ruling `AI-B`) — on AppKit
    /// the Dock's, on SDL every window's, including windows opened later.
    /// `App.icon` is the only caller and guarantees the contract: ordered
    /// smallest area first, no two images of one `width × height`, and `[]`
    /// meaning "restore the platform's own icon as far as it can". Best effort:
    /// a platform that cannot apply an icon does not report it (`AI-D`).
    ///
    /// **No default implementation** (`AB-R`/`EV-AB`/`DN-C`'s reason): a
    /// conformer that forgets it fails to compile rather than silently showing
    /// the generic icon. Pinned by
    /// `aPlatformWithoutSetApplicationIconDoesNotCompile`. **Migration**: a
    /// conformer outside this repository adds
    /// `func setApplicationIcon(_: [ImageTexture]) {}`.
    func setApplicationIcon(_ images: [ImageTexture])
}

// RED-FIRST SKELETON — removed by the implementation commit.
extension Platform {
    public func setApplicationIcon(_ images: [ImageTexture]) {}
}

/// Why a platform could not open a window.
public enum PlatformError: Error, CustomStringConvertible {
    case windowCreationFailed
    public var description: String { "could not create a platform window" }
}

/// What a window's frames are drawn with (ruling RS-A): one scene and the
/// glyph atlas it samples, into the window's drawable. `Window` calls
/// ``beginFrame()`` before building a frame — it needs the scale factor the
/// frame will be drawn at — and ``finishFrame(scene:atlas:)`` after.
@MainActor
public protocol WindowRenderer: AnyObject {
    /// Acquires the next drawable and returns its device scale factor, or
    /// `nil` when none is available this tick; the window stays dirty and
    /// retries, and ``finishFrame(scene:atlas:)`` is not called.
    func beginFrame() -> Float?

    /// Uploads `atlas` if it changed, draws `scene` into the drawable
    /// ``beginFrame()`` acquired, and presents it. `false` means the frame was
    /// not drawn; the window stays dirty and retries.
    func finishFrame(scene: Scene, atlas: GlyphAtlas) -> Bool
}
