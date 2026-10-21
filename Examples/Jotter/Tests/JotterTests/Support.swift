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
                  colorScheme: ColorScheme = .light, size: Size<Pixels> = jotterSize) throws -> TestWindow {
    #if os(Linux) || os(Windows)
    let resolver = try SystemFonts.resolver()
    return try TestWindow(size: size, colorScheme: colorScheme, options: options,
                          textSystem: { PortableTextSystem(resolver: resolver) }) { rootView(model: model) }
    #else
    return try TestWindow(size: size, colorScheme: colorScheme, options: options) { rootView(model: model) }
    #endif
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
