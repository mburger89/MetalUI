import Foundation
import MetalUICore
import MetalUIPlatform
import MetalUIPortableText
import MetalUIScene
@testable import MetalUI

// A `PlatformWindow` with no Metal, AppKit or SDL behind it, so a `Window`'s
// input pipeline and frame loop run on Linux and Windows CI (key and focus
// scoping, spec §5: the portable copies A37, and lane B's T13). Its renderer
// draws nothing and presents every frame; text goes through the portable text
// system over Noto Sans, the font `RichTextPortableWindowTests` uses.

private let portableFontURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Fonts/NotoSans-Regular.ttf")

/// A renderer that draws nothing: every frame begins at scale 1 and presents.
final class PortableNullRenderer: WindowRenderer {
    private(set) var framesFinished = 0
    func beginFrame() -> Float? { 1 }
    func finishFrame(scene: Scene, atlas: GlyphAtlas, surfaces: [SurfaceDrawRequest]) -> Bool {
        framesFinished += 1
        return true
    }
}

/// Every `PlatformWindow` requirement, answered honestly for a window nobody
/// sees: menus, dialogs, alerts and the toolbar are declined (`false`), so the
/// window draws its own, as under SDL.
@MainActor
final class PortableFakeWindow: PlatformWindow {
    var contentSize: Size<Pixels>
    var scaleFactor: Float = 1
    let nullRenderer = PortableNullRenderer()
    var renderer: any WindowRenderer { nullRenderer }
    var title = "Portable"
    var appearance: Appearance = .light
    var onInput: ((InputEvent) -> Bool)?
    var onResize: ((Size<Pixels>, Float) -> Void)?
    var onAppearanceChange: ((Appearance) -> Void)?
    var controlActiveState: ControlActiveState = .key
    var onControlActiveStateChange: ((ControlActiveState) -> Void)?
    var accessibilityReduceMotion = false
    var onAccessibilityReduceMotionChange: ((Bool) -> Void)?
    var accessibilityReduceTransparency = false
    var onAccessibilityReduceTransparencyChange: ((Bool) -> Void)?
    var onClose: (() -> Void)?
    var onAccessibilityRequest: ((AccessibilityRequest) -> Bool)?
    private var tick: ((Double) -> Void)?
    private(set) var clipboard: String?

    init(size: Int) {
        contentSize = Size(width: Pixels(Float(size)), height: Pixels(Float(size)))
    }

    func setPreferredColorScheme(_ colorScheme: ColorScheme?) {}
    func publishAccessibilityTree(_ tree: AccessibilityTree) {}
    func setTextInputArea(_ caret: Bounds<Pixels>?) {}
    func readClipboard() -> String? { clipboard }
    func writeClipboard(_ text: String) { clipboard = text }
    private(set) var clipboardRepresentations: [ClipboardRepresentation] = []
    private(set) var clipboardCommandRequests: [ClipboardCommands] = []
    func writeClipboard(_ representations: [ClipboardRepresentation]) -> Bool {
        guard !representations.isEmpty else { return false }
        clipboardRepresentations = representations
        return true
    }
    func clipboardTypeIdentifiers() -> [String] { clipboardRepresentations.map(\.type.identifier) }
    func readClipboard(identifier: String) -> [UInt8]? {
        clipboardRepresentations.first { $0.type.identifier == identifier }?.bytes
    }
    func setClipboardCommands(_ commands: ClipboardCommands) { clipboardCommandRequests.append(commands) }
    func startDisplayLink(_ tick: @escaping (Double) -> Void) { self.tick = tick }
    func setDisplayLinkPaused(_ paused: Bool) {}
    func beginExternalDrag(_ representations: [DragRepresentation], at position: Point<Pixels>) -> Bool { false }
    func presentMenu(_ menu: PlatformMenu, at position: Point<Pixels>) -> Bool { false }
    func presentFileDialog(_ dialog: PlatformFileDialog) -> Bool { false }
    func presentAlert(_ alert: PlatformAlert) -> Bool { false }
    func dismissPresentation(token: Int) {}
    func setContentSizeLimits(minimum: Size<Pixels>?, maximum: Size<Pixels>?) {}
    func setToolbar(_ toolbar: PlatformToolbar?) -> Bool { false }
    func setPointerStyle(_ style: PlatformPointerStyle) {}
    var onCloseRequest: (() -> Bool)?
    func close() { onClose?() }
    func setDocumentEdited(_ edited: Bool) {}
    func setRepresentedFilePath(_ path: String?) {}
    func setTitleBarStyle(_ style: PlatformTitleBarStyle) -> Bool { false }
    var titleBarInsets: Edges<Pixels> { Edges(all: Pixels(0)) }
    func performTitleBarPress(clickCount: Int) -> Bool { false }
    func performWindowDrag() -> Bool { false }
    func setWindowDragRegions(_ regions: [Bounds<Pixels>]) -> Bool { false }
    func performWindowAction(_ action: PlatformWindowAction) -> Bool { false }
    var hasNativeWindowControls: Bool { true }
    var isZoomed: Bool { false }

    /// Delivers `event` as a platform would.
    @discardableResult
    func simulateInput(_ event: InputEvent) -> Bool { onInput?(event) ?? false }

    /// Fires the display link at `timestamp` (the window must be built with
    /// `startsDisplayLink: true`).
    func simulateTick(timestamp: Double) { tick?(timestamp) }

    /// Resizes the content and reports it, as a live resize does.
    func simulateResize(to size: Size<Pixels>) {
        contentSize = size
        onResize?(size, scaleFactor)
    }
}

/// A `Window` over a `PortableFakeWindow` of `size` points, drawing text
/// through the portable text system.
@MainActor
func makePortableWindow<Root: Element>(size: Int = 200, startsDisplayLink: Bool = false,
                                       content: @escaping @MainActor () -> Root) throws
    -> (Window, PortableFakeWindow) {
    let platform = PortableFakeWindow(size: size)
    let system = PortableTextSystem(resolver: try PortableFontResolver(
        defaultFont: [UInt8](Data(contentsOf: portableFontURL))))
    let window = Window(platformWindow: platform, startsDisplayLink: startsDisplayLink,
                        textSystem: system, content: content)
    return (window, platform)
}
