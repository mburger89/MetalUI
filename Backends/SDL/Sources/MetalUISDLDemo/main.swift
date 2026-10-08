// The MetalUI demo on SDL3 (ruling DC-C): the same `demoContent()` the AppKit
// demo shows, drawn by `SDLWindowRenderer` with text from `PortableTextSystem`
// — the configuration a MetalUI app has on Linux and Windows. Runs on macOS
// too. Keys: F / Escape focus, = and - count (while focused), Space theme,
// M modal, A animation, Q quit. `METALUI_METALVIEW_DEMO=1`: MetalView's demo
// (ruling MV-J) — app GPU surfaces drawn through `SDLGPUDrawContext`.
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
    // The demo's generated icon (ruling `AI-G`; human checks O2–O4): every
    // window's icon, and on macOS the Dock's.
    app.icon = demoIcon()
    // `METALUI_DND_DEMO=1`: drag and drop's chips and wells (ruling DN-Q) —
    // drops from other applications arrive through SDL's drop events (DN-M);
    // a chip cannot leave the window (divergence 101).
    // `METALUI_TEXT_INPUT_DEMO=1`: roadmap item 14's two text fields (TI-F).
    // `METALUI_MENUS_DEMO=1`: menus, popovers and tooltips (human check R2) —
    // the context menu is drawn in the window (`MN-F`); SDL has no menu bar.
    // `METALUI_METALVIEW_DEMO=1`: MetalView's demo (ruling MV-J, human checks
    // section O) — the large surface clears to a colour cycling with
    // `ctx.time` through the SDL renderer's draw context; the counter and the
    // drawing are made once, outside the content closure that runs every
    // frame (MV-O item 1).
    // `METALUI_SERVICES_DEMO=1`: platform services (human checks U3, U5, U7–U10,
    // ruling SV-T) — SDL's desktop file dialogs, the drawn alert, hover tiles,
    // dividers and the drawn, scrolling menu picker; a 900 × 600 minimum.
    // `METALUI_LOOKS_DEMO=1`: the looks demo (human check S4 — the colour
    // section's swatches and scheme toggle; the window's decorations stay with
    // the system theme, `CR-M`), with the app's dark palette override.
    // `METALUI_RICH_TEXT_DEMO=1`: rich text (human check RT4, ruling RT-O item
    // 10) — through the portable text system; a code span draws the default
    // face unless a monospaced family is registered (`TE-B`, `RT-O` item 12).
    // `METALUI_LIST_DEMO=1`: the variable-height list (human checks VL1–VL5,
    // ruling VL-K) — content-sized rows of wrapping text, selectable, a jump.
    let environment = ProcessInfo.processInfo.environment
    let size = Size(width: Pixels(920), height: Pixels(560))
    let metalViewDraws = MetalViewDemoDraws()
    let metalViewSurface: @MainActor (any GPUSurfaceContext) -> Void = { ctx in
        let t = Float(ctx.time.truncatingRemainder(dividingBy: 3600))
        ctx.clear(red: 0.5 + 0.5 * sin(t), green: 0.5 + 0.5 * sin(t + 2.1), blue: 0.5 + 0.5 * sin(t + 4.2),
                  alpha: 1)
    }
    if environment["METALUI_LOOKS_DEMO"] == "1" {
        app.darkTheme[LooksBrand.self] = looksBrandDarkOverride
    }
    let window = environment["METALUI_RICH_TEXT_DEMO"] == "1"
        ? try app.openWindow(title: "MetalUI — SDL3 rich text", size: Size(width: Pixels(920), height: Pixels(640)),
                             content: richTextDemoContent)
        : environment["METALUI_LIST_DEMO"] == "1"
        ? try app.openWindow(title: "MetalUI — SDL3 variable-height List", size: size,
                             content: variableListDemoContent)
        : environment["METALUI_SERVICES_DEMO"] == "1"
        ? try openServicesDemoWindow(app, title: "MetalUI — SDL3 platform services")
        : environment["METALUI_LOOKS_DEMO"] == "1"
        ? try app.openWindow(title: "MetalUI — SDL3 looks", size: Size(width: Pixels(1180), height: Pixels(880)),
                             content: looksDemoContent)
        : environment["METALUI_METALVIEW_DEMO"] == "1"
        ? try app.openWindow(title: "MetalUI — SDL3 MetalView", size: size,
                             content: { metalViewDemoContent(draws: metalViewDraws, surface: metalViewSurface) })
        : environment["METALUI_DND_DEMO"] == "1"
        ? try app.openWindow(title: "MetalUI — SDL3 drag and drop", size: size, content: dragAndDropDemoContent)
        : environment["METALUI_MENUS_DEMO"] == "1"
        ? try app.openWindow(title: "MetalUI — SDL3 menus", size: size, content: menusDemoContent)
        : environment["METALUI_TEXT_INPUT_DEMO"] == "1"
        ? try app.openWindow(title: "MetalUI — SDL3 text input", size: size, content: textInputDemoContent)
        : try app.openWindow(title: "MetalUI — SDL3", size: size, content: demoContent)
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
