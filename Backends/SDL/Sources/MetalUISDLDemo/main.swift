// The MetalUI demo on SDL3 (ruling DC-C): the same `demoContent()` the AppKit
// demo shows, drawn by `SDLWindowRenderer` with text from `PortableTextSystem`
// — the configuration a MetalUI app has on Linux and Windows. Runs on macOS
// too. Keys: F / Escape focus, = and - count (while focused), Space theme,
// M modal, A animation, Q quit.
import Foundation
import MetalUI
import MetalUIDemoContent
import MetalUIPortableText
import MetalUISDL
import MetalUISystemFonts

let fonts = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Tests/Fonts")

@MainActor
func runDemo() throws {
    func bytes(_ name: String) throws -> [UInt8] {
        [UInt8](try Data(contentsOf: fonts.appendingPathComponent(name)))
    }
    // `METALUI_SYSTEM_FONTS=1`: the platform's installed fonts (roadmap item
    // 8b, SF-A…SF-D) instead of the repository's three.
    let resolver: PortableFontResolver
    if ProcessInfo.processInfo.environment["METALUI_SYSTEM_FONTS"] == "1" {
        resolver = try SystemFonts.resolver()
    } else {
        resolver = try PortableFontResolver(defaultFont: bytes("NotoSans-Regular.ttf"))
        try resolver.register(bytes("SourceSans3-Regular.otf"))
        try resolver.register(bytes("NotoSansArabic-Regular.ttf"))
    }

    let platform = try SDLPlatform()
    let app = App(platform: platform, textSystem: { PortableTextSystem(resolver: resolver) })
    // `METALUI_TEXT_INPUT_DEMO=1`: roadmap item 14's two text fields (TI-F).
    let window = ProcessInfo.processInfo.environment["METALUI_TEXT_INPUT_DEMO"] == "1"
        ? try app.openWindow(title: "MetalUI — SDL3 text input", size: Size(width: Pixels(920), height: Pixels(560)),
                             content: textInputDemoContent)
        : try app.openWindow(title: "MetalUI — SDL3", size: Size(width: Pixels(920), height: Pixels(560)),
                             content: demoContent)
    window.keymap = Keymap {
        KeyBinding("=", Increment(), context: "Counter")
        KeyBinding("shift-+", Increment(), context: "Counter")
        KeyBinding("-", Decrement(), context: "Counter")
        KeyBinding("f", FocusCounter())
        KeyBinding("escape", ClearFocus())
        KeyBinding("space", ToggleTheme())
        KeyBinding("m", ToggleModal())
        KeyBinding("a", ToggleAnimationDemo())
        KeyBinding("q", QuitDemo())
    }
    window.onAction = { [weak window] action in
        guard let window else { return false }
        switch action {
        case is ToggleTheme: window.theme = window.theme == .dark ? .light : .dark
        case is ToggleModal: demoModel.showModal.toggle()
        case is ToggleAnimationDemo:
            withAnimation(.spring(duration: 0.6, bounce: 0.2)) { demoModel.animationDemoActive.toggle() }
        case is FocusCounter: window.focus(counterID)
        case is ClearFocus: window.focus(nil)
        case is QuitDemo: platform.stop()
        default: return false
        }
        return true
    }
    demoWindow = window
    app.run()
}

do { try MainActor.assumeIsolated { try runDemo() } } catch {
    print("ERROR: \(error)")
    exit(1)
}
