import Foundation
import JotterKit
import MetalUI
import MetalUITesting
#if os(Linux) || os(Windows)
import MetalUIPortableText
import MetalUISystemFonts
#endif

/// The window size the tests open at: the app's own default.
let jotterSize = jotterWindowSize

/// A model with the four seeded notes and a fixed "today", so no test reads a clock.
@MainActor
func seededModel() -> NotesModel { NotesModel.seeded(today: { 20_000 }) }

/// The app's real root element in a headless window. Text goes through CoreText
/// on macOS and, as in `main.swift`, the portable text system over the
/// installed fonts on Linux and Windows.
@MainActor
func jotterWindow(_ model: NotesModel, options: HeadlessPlatformWindow.Options = .init(),
                  colorScheme: ColorScheme = .light, size: Size<Pixels> = jotterSize,
                  recordsLayout: Bool = true) throws -> TestWindow {
    #if os(Linux) || os(Windows)
    let resolver = try SystemFonts.resolver()
    return settled(try TestWindow(size: size, colorScheme: colorScheme, options: options, recordsLayout: recordsLayout,
                                  textSystem: { PortableTextSystem(resolver: resolver) }) { rootView(model: model) })
    #else
    return settled(try TestWindow(size: size, colorScheme: colorScheme, options: options, recordsLayout: recordsLayout) { rootView(model: model) })
    #endif
}

/// Draws the frames a window needs to settle. A `List` measures its own origin in its first frame and
/// asks for one more before it builds its rows; AppKit's observation hop gives that frame at once, and
/// off macOS the test asks for it (record 136, finding 13: Linux showed no rows in the first frame).
@MainActor
func settled(_ window: TestWindow) -> TestWindow {
    window.tick()
    window.tick()
    return window
}

/// The sidebar's rows, top to bottom, as their note ids (rows are named `note-<uuid>`).
@MainActor
func rowIDs(_ window: TestWindow) throws -> [String] {
    try window.elements { ($0.identifier ?? "").hasPrefix("note-") }.compactMap { $0.identifier }
}

/// The accessibility identifier of the row for `note`.
func rowIdentifier(_ note: Note) -> String { "note-\(note.id.uuidString)" }

/// A scratch directory unique to one test.
func scratchFile(_ name: String) -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("jotter-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent(name)
}

/// The app and its window together, with the menu bar's commands installed as
/// `main.swift` installs them: what a test of a shortcut or a menu item needs.
@MainActor
func jotterApp(_ model: NotesModel, options: HeadlessPlatformWindow.Options? = nil) throws -> (app: TestApp, window: TestWindow) {
    #if os(Linux) || os(Windows)
    let resolver = try SystemFonts.resolver()
    let testApp = try TestApp(textSystem: { PortableTextSystem(resolver: resolver) })
    #else
    let testApp = try TestApp()
    #endif
    installJotterCommands(on: testApp.app, model: model)
    let window = try testApp.openWindow(title: "Jotter", size: jotterWindowSize, minSize: jotterMinimumSize,
                                        options: options) { rootView(model: model) }
    return (testApp, settled(window))
}

/// The centre of an element's frame, in window points.
func centre(of element: TestElement) -> Point<Pixels> {
    Point(x: element.frame.origin.x + element.frame.size.width / 2, y: element.frame.origin.y + element.frame.size.height / 2)
}
