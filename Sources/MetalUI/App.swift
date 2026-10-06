import MetalUIPlatform
#if canImport(MetalUIAppKit)
import AppKit
import Metal
import MetalUIAppKit
#endif

// MetalUI is the umbrella module: a client writes `import MetalUI` and gets the
// geometry, unit and colour types its elements must name, the `Style` values
// its modifiers write, the `Scene` its paint fills, and — since the window grew
// an `onInput` hook — the `InputEvent` that hook is handed.
@_exported import MetalUICore
@_exported import MetalUILayout
@_exported import MetalUIPlatform
@_exported import MetalUIPrimitives
@_exported import MetalUITextSystem
#if canImport(MetalUIRender)
@_exported import MetalUIRender
#endif

/// Why an `App` could not be created.
public enum AppError: Error, CustomStringConvertible {
    case noMetalDevice
    public var description: String { "no Metal device is available on this system" }
}

/// An application: one platform, its windows, and the text engine every
/// window draws with (ruling XP-B). On macOS the default is AppKit with Metal
/// and CoreText; anywhere, ``init(platform:textSystem:)`` takes any
/// `Platform` — `Backends/SDL`'s `SDLPlatform` on Linux and Windows — and a
/// `TextSystem`, which a non-Apple build must supply (it has no CoreText).
@MainActor
public final class App {
    let platform: any Platform
    private var windows: [Window] = []
    /// Makes each window's text engine (ruling TS-A); `nil` is CoreText.
    private let makeTextSystem: (@MainActor () -> any TextSystem)?
    /// Whether closing the last window ends the process through AppKit.
    private let terminatesThroughAppKit: Bool
    /// The menu bar's commands, `nil` until `commands(content:)` (ruling
    /// `MN-I`); re-evaluated whenever the bar's content is needed.
    var commandsContent: (@MainActor () -> any Commands)?
    /// The command items' actions from the bar's last evaluation, by item id —
    /// what `PlatformMenuBar.perform` runs (spec §3.6).
    var menuBarActions: [Int: @MainActor () -> Void] = [:]

    #if canImport(MetalUIAppKit)
    /// The Metal device the AppKit platform draws with; `nil` for an app on
    /// another platform.
    public let device: (any MTLDevice)?

    /// An app on the system default Metal device with AppKit and CoreText;
    /// throws `AppError.noMetalDevice` when the system has no Metal device.
    public convenience init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw AppError.noMetalDevice }
        try self.init(device: device)
    }

    /// - Parameter textSystem: makes the text engine every window of this app
    ///   measures and draws through — once per window, since each keeps its
    ///   own caches. `nil` (the default) is CoreText; a `PortableTextSystem`
    ///   draws with HarfBuzz, FreeType and libunibreak instead, the path a
    ///   non-Apple platform takes.
    public init(device: any MTLDevice, textSystem: (@MainActor () -> any TextSystem)? = nil) throws {
        self.device = device
        self.makeTextSystem = textSystem
        self.platform = AppKitPlatform(renderer: try Renderer(device: device))
        self.terminatesThroughAppKit = true
        installMenuBar()   // MN-I item 4: every app has the default bar
    }

    /// An app on `platform` — the SDL platform on macOS too — drawing text
    /// with `textSystem` (`nil`: CoreText).
    public init(platform: any Platform, textSystem: (@MainActor () -> any TextSystem)? = nil) {
        self.device = nil
        self.makeTextSystem = textSystem
        self.platform = platform
        self.terminatesThroughAppKit = platform is AppKitPlatform
        installMenuBar()   // MN-I item 4
    }
    #else
    /// An app on `platform` — `Backends/SDL`'s `SDLPlatform` — drawing text
    /// with `textSystem`, which is required here: there is no CoreText to fall
    /// back on (ruling XP-B).
    public init(platform: any Platform, textSystem: @escaping @MainActor () -> any TextSystem) {
        self.makeTextSystem = textSystem
        self.platform = platform
        self.terminatesThroughAppKit = false
        installMenuBar()   // MN-I item 4
    }
    #endif

    /// Opens a window whose content is one root element, rebuilt every frame.
    ///
    /// `content` is a plain closure and **not** `@ElementBuilder`-annotated. The
    /// builder's job is to fold several children into one group — `Pair`,
    /// `ArrayGroup` — and a group is not an `Element`, so a two-statement block
    /// here would fail to satisfy `Root: Element` with a diagnostic about
    /// `Pair` rather than about the window. A window has exactly one root;
    /// wrapping several children in a `Column` says so at the call site.
    ///
    /// **Sizing** (ruling `SV-L`; SwiftUI's `.defaultSize` and
    /// `.windowResizability` scene modifiers, `App` not being a `Scene`):
    /// `size` is the default content size (`W3`); `minSize`/`maxSize` limit it
    /// and `windowResizability` lets the root's layout limit it too — each
    /// also settable later on the returned `Window`. Limits given here reach
    /// the platform before the first frame.
    @discardableResult
    public func openWindow<Root: Element>(
        title: String,
        size: Size<Pixels>,
        minSize: Size<Pixels>? = nil,
        maxSize: Size<Pixels>? = nil,
        windowResizability: WindowResizability = .automatic,
        startsDisplayLink: Bool = true,
        content: @escaping @MainActor () -> Root
    ) throws -> Window {
        let platformWindow = try platform.openWindow(title: title, size: size)
        let window = Window(platformWindow: platformWindow,
                            startsDisplayLink: startsDisplayLink,
                            textSystem: makeTextSystem?(),
                            content: content)
        // Before the first frame (`SV-L` item 4): the platform clamps the
        // window into explicit limits before anything is drawn at its size.
        window.applySizing(minSize: minSize, maxSize: maxSize, windowResizability: windowResizability)
        // A command's shortcut reaches this window's command stage (ruling
        // `MN-J`), evaluated afresh at each keystroke that gets that far.
        window.commandShortcuts = { [weak self] in self?.enabledCommandShortcuts() ?? [] }
        // Closing the last window must end the process: there is no app
        // delegate, so on SDL this close button is the only way out (AppKit's
        // menu bar also has Quit since `MN-I` — this comment's earlier "no menu
        // bar anywhere in the framework" is corrected). AppKit's run loop is
        // ended here; SDL's `run()` returns on its own once its last window has
        // closed.
        let terminates = terminatesThroughAppKit
        platformWindow.onClose = { [weak window] in
            // Every present `onDisappear` runs once before anything ends
            // (ruling `LC-J`): the window's content leaves with it (`W3`).
            window?.runDisappearancesForClose()
            #if canImport(AppKit)
            if terminates { NSApplication.shared.terminate(nil) }
            #endif
        }
        windows.append(window)
        // The app's scheme and themes reach the window before its first frame
        // (rulings `CR-L` item 4, `CR-N` item 4), so it never presents in the
        // platform's scheme first.
        window.lightTheme = lightTheme
        window.darkTheme = darkTheme
        window.preferredColorScheme = preferredColorScheme

        // Paint once now rather than waiting for a display-link tick. The link
        // does not fire while the view is hidden or off-display, which would
        // otherwise leave a window that opens occluded blank indefinitely. The
        // surface geometry is already valid from the platform window's init, and
        // a missing drawable simply leaves the window dirty for the link to retry.
        window.drawFrameIfNeeded()
        return window
    }

    /// The application's icon (ruling `AI-A`): several sizes of one picture,
    /// shown by the operating system as the application's — the Dock icon on
    /// macOS, every window's icon on SDL (Linux, Windows; on macOS SDL also
    /// sets the Dock's). `[]`, the default, is the platform's own icon: the
    /// bundle's, else the system's generic one.
    ///
    /// Every assignment reaches the platform at once, synchronously, before or
    /// after windows open (`AI-C`); an `App` that never assigns it never
    /// touches the platform's icon, so a bundled app's own icon is never
    /// overwritten at launch. The platform receives the bitmaps' own textures
    /// ordered smallest area first, a repeated `width × height` dropped (the
    /// first written wins); the property itself reads back exactly what was
    /// assigned. On SDL, `[]` cannot clear an icon already shown (`AI-F`
    /// item 5).
    ///
    /// **MetalUI-only**: SwiftUI has no runtime icon API — a SwiftUI app's
    /// icon is its bundle's (an asset catalog's `AppIcon`, or
    /// `CFBundleIconFile`); this is AppKit's runtime override,
    /// `NSApplication.applicationIconImage`, made portable. Shipping a bundle
    /// with its own icon is build-side: `docs/packaging.md`.
    public var icon: [ImageBitmap] = [] {
        didSet { platform.setApplicationIcon(App.normalized(icon)) }
    }

    /// A preferred colour scheme for every window of this app (ruling `CR-L`
    /// item 4, MetalUI-only — SwiftUI spells it as a scene's root
    /// `.preferredColorScheme`): each assignment sets every open window's
    /// `Window.preferredColorScheme`, and each later window gets it before
    /// its first frame, so it never flashes the platform's scheme. A tree's
    /// own `.preferredColorScheme` still wins inside its window. `nil` (the
    /// default) follows the platform.
    public var preferredColorScheme: ColorScheme? {
        didSet { for window in windows { window.preferredColorScheme = preferredColorScheme } }
    }

    /// The light theme of every window of this app (ruling `CR-N` item 4,
    /// MetalUI-only; default `.light`): each assignment — a palette override
    /// `app.lightTheme[Key.self] = …` included — sets every open window's
    /// `Window.lightTheme`, and each later window gets it before its first
    /// frame.
    public var lightTheme: Theme = .light {
        didSet { for window in windows { window.lightTheme = lightTheme } }
    }

    /// The dark theme of every window of this app (ruling `CR-N` item 4;
    /// default `.dark`). See ``lightTheme``.
    public var darkTheme: Theme = .dark {
        didSet { for window in windows { window.darkTheme = darkTheme } }
    }

    /// The platform contract of ``icon`` (`AI-C` item 3): the bitmaps' own
    /// textures (no copy), sorted by `width × height` ascending and stable, a
    /// bitmap repeating an earlier `(width, height)` pair dropped — the first
    /// written wins.
    static func normalized(_ bitmaps: [ImageBitmap]) -> [ImageTexture] {
        var seen: [(Int, Int)] = []
        var kept: [(index: Int, texture: ImageTexture)] = []
        for (index, bitmap) in bitmaps.enumerated()
        where !seen.contains(where: { $0 == (bitmap.width, bitmap.height) }) {
            seen.append((bitmap.width, bitmap.height))
            kept.append((index, bitmap.texture))
        }
        return kept.sorted {
            let (a, b) = ($0.texture.width * $0.texture.height, $1.texture.width * $1.texture.height)
            return a != b ? a < b : $0.index < $1.index
        }.map(\.texture)
    }

    /// Runs the platform's event loop, handing every window its input and
    /// display-link ticks until the platform stops.
    ///
    /// **Call it from synchronous top-level code** (`main.swift`), not from an
    /// `async` main: inside a main-actor job neither platform's loop can drain
    /// the main queue, so a main-actor `Task` — or an awaited `FileDialogs`
    /// call's continuation — never runs (ruling `SV-H` item 2; probe
    /// `swift-main-queue-drain-nested.swift` `J1`, `J3`).
    public func run() {
        platform.run()
    }
}
