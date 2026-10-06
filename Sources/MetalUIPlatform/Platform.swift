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

    /// Asks the platform to present this window in `colorScheme`, or — `nil`
    /// — to follow the application's appearance again (ruling `CR-M`).
    /// `Window` calls it whenever its requested scheme (the tree's
    /// `.preferredColorScheme`, else `Window.preferredColorScheme`) changes,
    /// and only then. AppKit sets `NSWindow.appearance`, so the title bar and
    /// native menus follow, and reports the forced appearance back through
    /// `onAppearanceChange`; SDL3 has no per-window appearance, so `SDLWindow`
    /// records the value and keeps reporting the system theme — content
    /// follows the preference through `Window`, decorations follow the system.
    ///
    /// **No default implementation** (`EV-AB`'s reason): a conformer that
    /// forgets it fails to compile rather than silently ignoring a preference.
    /// Pinned by `aPlatformWindowWithoutSetPreferredColorSchemeDoesNotCompile`.
    /// **Migration**: a conformer outside this repository adds
    /// `func setPreferredColorScheme(_ colorScheme: ColorScheme?) {}`.
    func setPreferredColorScheme(_ colorScheme: ColorScheme?)

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

    /// Shows `menu` itself at `position` (window points, the menu's top-left
    /// corner) and answers whether it did (ruling `MN-C`). `false` — SDL, which
    /// has no menu API — means "draw it yourself", and `Window` opens its
    /// in-window menu (`MN-F`). A choice comes back later as
    /// `InputEvent.menuAction`, delivered after this call returned, never
    /// inside it (`MN-C` item 4).
    ///
    /// **No default implementation** (`MN-C` item 1, `EV-AB`'s reason): a
    /// conformer that forgets it fails to compile rather than silently never
    /// showing a menu. Pinned by
    /// `aPlatformWindowWithoutPresentMenuDoesNotCompile`. **Migration**: a
    /// conformer outside this repository adds
    /// `func presentMenu(_: PlatformMenu, at: Point<Pixels>) -> Bool { false }`.
    func presentMenu(_ menu: PlatformMenu, at position: Point<Pixels>) -> Bool

    /// Shows the open or save dialog `dialog` describes and answers whether it
    /// did (ruling `SV-B`). `true`: the platform answers later with exactly
    /// one `InputEvent.fileDialogResult` carrying `dialog.token`, delivered
    /// after this call returned, never inside it — AppKit attaches an
    /// `NSOpenPanel`/`NSSavePanel` sheet (`SV-F`), SDL calls
    /// `SDL_ShowOpenFileDialog`/`SDL_ShowSaveFileDialog` and hops the answer
    /// onto the main thread as an event (`SV-G`). `false`: it cannot (AppKit
    /// while another sheet is attached), and `MetalUI` completes the request
    /// with `FileDialogError.unavailable`.
    ///
    /// **No default implementation** (`SV-B` item 1, `EV-AB`'s reason): a
    /// conformer that forgets it fails to compile rather than silently never
    /// showing a dialog. Pinned by
    /// `aPlatformWindowWithoutPresentFileDialogDoesNotCompile`. **Migration**:
    /// a conformer outside this repository adds
    /// `func presentFileDialog(_: PlatformFileDialog) -> Bool { false }`.
    func presentFileDialog(_ dialog: PlatformFileDialog) -> Bool

    /// Shows `alert` natively and answers whether it did (ruling `SV-B`,
    /// `presentMenu`'s contract). `true`: the platform answers later with
    /// exactly one `InputEvent.alertResult` carrying `alert.token` — AppKit
    /// attaches an `NSAlert` sheet whose key equivalents are exactly the
    /// buttons' roles (`SV-J` item 1, `SV-X`). `false` — SDL, whose message box
    /// blocks in a nested loop — means "draw it yourself", and `Window` draws
    /// its in-window alert (`SV-J` item 2).
    ///
    /// **No default implementation** (`SV-B` item 1): pinned by
    /// `aPlatformWindowWithoutPresentAlertDoesNotCompile`. **Migration**: a
    /// conformer outside this repository adds
    /// `func presentAlert(_: PlatformAlert) -> Bool { false }`.
    func presentAlert(_ alert: PlatformAlert) -> Bool

    /// Ends the dialog or alert `token` names without an answer (ruling
    /// `SV-B`): AppKit ends the sheet and suppresses its completion. A platform
    /// that cannot close one — SDL3 has no call for its file dialogs (`SV-G`
    /// item 5) — does nothing, and the answer that eventually arrives is
    /// delivered as usual; `Window` has forgotten the token and runs nothing.
    ///
    /// **No default implementation** (`SV-B` item 1): pinned by
    /// `aPlatformWindowWithoutDismissPresentationDoesNotCompile`.
    /// **Migration**: a conformer outside this repository adds
    /// `func dismissPresentation(token: Int) {}`.
    func dismissPresentation(token: Int)

    /// Limits the window's content size, in window points (ruling `SV-M`):
    /// `nil` lifts that limit. A window whose content lies outside the new
    /// limits is resized into them by the platform, and the resize reaches
    /// `Window` through `onResize` — AppKit sets `contentMinSize`/
    /// `contentMaxSize` and resizes, SDL calls `SDL_SetWindowMinimumSize`/
    /// `SDL_SetWindowMaximumSize` (minimum rounded up, maximum down). `Window`
    /// calls it only when the effective limits change (`SV-L` item 4); the
    /// values are finite and non-negative, the maximum never below the
    /// minimum, an unbounded axis of a maximum `Float.greatestFiniteMagnitude`.
    ///
    /// **No default implementation** (`SV-B` item 1): pinned by
    /// `aPlatformWindowWithoutSetContentSizeLimitsDoesNotCompile`.
    /// **Migration**: a conformer outside this repository adds
    /// `func setContentSizeLimits(minimum: Size<Pixels>?, maximum: Size<Pixels>?) {}`.
    func setContentSizeLimits(minimum: Size<Pixels>?, maximum: Size<Pixels>?)

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

    /// Installs the application's menu bar (ruling `MN-I`): AppKit builds
    /// `NSApp.mainMenu` from `menuBar.content()`, rebuilding a menu each time
    /// it opens, and runs a chosen command item through `menuBar.perform`;
    /// SDL records it and draws nothing (Linux and Windows SDL windows have no
    /// menu bar — a command's shortcut still works through `Window`, `MN-J`).
    /// `App` calls it once at init and again from `App.commands(content:)`; a
    /// later call replaces the bar.
    ///
    /// **No default implementation** (`AB-R`/`EV-AB`/`DN-C`'s reason): a
    /// conformer that forgets it fails to compile rather than silently showing
    /// no menu bar. Pinned by `aPlatformWithoutSetMenuBarDoesNotCompile`.
    /// **Migration**: a conformer outside this repository adds
    /// `func setMenuBar(_: PlatformMenuBar) {}`.
    func setMenuBar(_ menuBar: PlatformMenuBar)
}

/// Why a platform could not open a window.
public enum PlatformError: Error, CustomStringConvertible {
    case windowCreationFailed
    public var description: String { "could not create a platform window" }
}

/// What a window's frames are drawn with (ruling RS-A): one scene and the
/// glyph atlas it samples, into the window's drawable. `Window` calls
/// ``beginFrame()`` before building a frame — it needs the scale factor the
/// frame will be drawn at — and ``finishFrame(scene:atlas:surfaces:)`` after.
@MainActor
public protocol WindowRenderer: AnyObject {
    /// Acquires the next drawable and returns its device scale factor, or
    /// `nil` when none is available this tick; the window stays dirty and
    /// retries, and ``finishFrame(scene:atlas:surfaces:)`` is not called.
    func beginFrame() -> Float?

    /// Uploads `atlas` if it changed, runs the frame's app-owned GPU
    /// `surfaces` (MetalView, ruling `MV-F`), draws `scene` into the drawable
    /// ``beginFrame()`` acquired, and presents it. `false` means the frame was
    /// not drawn; the window stays dirty and retries.
    ///
    /// `surfaces` are the frame's **app surfaces' draw requests**, in paint
    /// order — not the renderer's drawable (`MV-L`'s rejected finding). Each is
    /// resolved against the renderer's own per-window `SurfaceTargetTable`
    /// (`MV-E`) and drawn, on the main actor, into the frame's command buffer
    /// **before** the scene is encoded, so the app's pass completes before
    /// the composite samples it (`MV-F` item 3).
    ///
    /// **No default implementation** (`MV-F` item 1, `EV-AB`'s reason): a
    /// renderer that forgets surfaces fails to compile rather than drawing a
    /// blank viewport. Pinned by
    /// `aWindowRendererWithoutTheSurfacesFinishFrameDoesNotCompile`.
    /// **Migration** (`MV-K` item 3): an external conformer adds the
    /// parameter; one with no surface support may ignore it and composites
    /// nothing for surface runs.
    func finishFrame(scene: Scene, atlas: GlyphAtlas, surfaces: [SurfaceDrawRequest]) -> Bool
}

extension WindowRenderer {
    /// A frame with no app surfaces — so every existing **caller** compiles
    /// (`MV-F` item 1).
    public func finishFrame(scene: Scene, atlas: GlyphAtlas) -> Bool {
        finishFrame(scene: scene, atlas: atlas, surfaces: [])
    }
}
