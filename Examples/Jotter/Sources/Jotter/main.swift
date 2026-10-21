import JotterKit
import MetalUI
#if canImport(MetalUISDL)
import MetalUIPortableText
import MetalUISDL
import MetalUISystemFonts
#endif

/// AppKit and Metal on macOS; SDL3 with MetalUI's portable text, over the
/// platform's installed fonts, on Linux and Windows.
@MainActor
func makeApp() throws -> App {
    #if canImport(MetalUISDL)
    let resolver = try SystemFonts.resolver()
    return App(platform: try SDLPlatform(options: .headlessIfRequested()), textSystem: { PortableTextSystem(resolver: resolver) })
    #else
    return try App()
    #endif
}

// One model for the whole app, created here and handed to the views.
let model = NotesModel.seeded()
let app = try makeApp()
try app.openWindow(title: "Jotter", size: jotterWindowSize, minSize: jotterMinimumSize) { rootView(model: model) }
app.run()
