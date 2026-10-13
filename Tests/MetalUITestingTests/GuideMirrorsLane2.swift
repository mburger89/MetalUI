import MetalUI
import MetalUITesting
import Testing

// Lane 2 of the developer guides (item 10b; rulings `DG-C`…`DG-M`): the mirrors of the
// swift blocks of `docs/guides/presentations-and-app-shell.md`, `drawing-and-gpu.md` and
// `cross-platform.md`, copied BY HAND between the `// guide:` and `// end guide` markers,
// byte for byte, so the ordinary build compiles them on every platform;
// `GuideDocCheck.swift` compares each region with its guide. Below the regions, the tests
// that run the blocks in a headless window and prove the claims the guides pin to them.
// Change a guide and its mirror together. Every top-level name carries its guide's topic
// as prefix (`DG-K`: one module, both lanes). Mutations: delete the modifier a test names.

// guide: presentations-and-app-shell #1
import MetalUI

/// A button whose popover opens beside it.
struct ShellPopoverDemo: Component {
    @State var shown = false

    var content: some ElementGroup {
        Button("Info") { shown.toggle() }
            .popover(isPresented: $shown) {
                Text("Details").frame(width: Pixels(120), height: Pixels(40))
            }
    }
}

@MainActor
func shellPopoverRoot() -> some Element {
    VStack { ShellPopoverDemo() }
}
// end guide

// guide: presentations-and-app-shell #2
/// A destructive action behind a confirmation.
struct ShellDeleteConfirmation: Component {
    @State var asking = false
    @State var deleted = 0

    var content: some ElementGroup {
        Button("Remove") { asking = true }
            .alert("Delete the file?", isPresented: $asking) {
                Button("Delete", role: .destructive) { deleted += 1 }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        Text("Deleted \(deleted)")
    }
}

@MainActor
func shellDeleteRoot() -> some Element {
    VStack { ShellDeleteConfirmation() }
}
// end guide

// guide: presentations-and-app-shell #3
/// The path a file dialog chose, logged.
@MainActor
final class ShellLog {
    var entries: [String] = []
}

/// A button that asks for one JSON file.
struct ShellImporter: Component {
    @State var asking = false
    let log: ShellLog

    var content: some ElementGroup {
        Button("Import") { asking = true }
            .fileImporter(isPresented: $asking, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { log.entries.append("chose \(url.path)") }
            }
    }
}

@MainActor
func shellImportRoot(_ log: ShellLog) -> some Element {
    VStack { ShellImporter(log: log) }
}
// end guide

// guide: presentations-and-app-shell #4
/// A command menu: the title opens on a click off Apple, in the system bar on Apple.
@MainActor
func shellInstallCommands(_ app: App, log: ShellLog) {
    app.commands {
        CommandMenu("Tools") {
            Button("Run") { log.entries.append("run") }.keyboardShortcut("r")
        }
    }
}

/// A target with a one-item context menu.
@MainActor
func shellContextMenuRoot(_ log: ShellLog) -> some Element {
    VStack {
        Button("Target") {}
            .contextMenu {
                Button("Copy") { log.entries.append("copy") }
            }
    }
}
// end guide

// guide: presentations-and-app-shell #5
/// A titled root with one toolbar button.
@MainActor
func shellToolbarRoot(_ log: ShellLog) -> some Element {
    VStack {
        Text("Notes")
            .frame(width: Pixels(100), height: Pixels(50))
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(id: "add") { Button("Add") { log.entries.append("add") } }
            }
    }
}
// end guide

// guide: presentations-and-app-shell #6
/// A document whose window refuses to close while it has unsaved changes.
@MainActor
final class ShellDocument {
    var hasUnsavedChanges = false
}

@MainActor
func shellGuardClose(_ window: Window, document: ShellDocument) {
    window.onCloseRequest = { document.hasUnsavedChanges ? .cancel : .now }
}
// end guide

// MARK: Presentations and the app shell (T11)

/// **T11** — the shell guide's roots build. Mutation: rename `shellPopoverRoot`.
@Test @MainActor func theShellGuideBuildsInAHeadlessWindowAndItsClaimsHold() throws {
    _ = try harnessWindow { shellPopoverRoot() }
    _ = try harnessWindow { shellDeleteRoot() }
    _ = try harnessWindow { shellImportRoot(ShellLog()) }
    _ = try harnessWindow { shellContextMenuRoot(ShellLog()) }
    _ = try harnessWindow { shellToolbarRoot(ShellLog()) }
}

/// Pressing the button opens the popover, which is a presentation root inside the window.
/// Mutation: delete `.popover(isPresented: $shown)`.
@Test @MainActor func theShellGuideAPopoverOpensFromItsButton() throws {
    let window = try harnessWindow { shellPopoverRoot() }
    #expect(try window.elements(role: .popover).isEmpty, "closed at first")
    try window.click(window.element(label: "Info"))
    window.tick()
    #expect(try window.elements(role: .popover).count == 1)
    _ = try window.element(label: "Details")
}

/// The alert is read at the seam; its destructive button runs the action and closes it.
/// Mutation: delete `deleted += 1`.
@Test @MainActor func theShellGuideAnAlertsButtonRunsItsActionAndClosesIt() throws {
    let window = try harnessWindow { shellDeleteRoot() }
    try window.click(window.element(label: "Remove"))
    let alert = try #require(window.presentedAlert)
    #expect(alert.title == "Delete the file?")
    #expect(alert.buttons.map(\.title) == ["Delete", "Cancel"])
    try window.respondToAlert(button: "Delete")
    #expect(window.presentedAlert == nil)
    _ = try window.element(label: "Deleted 1")
}

/// A drawn alert (where the platform declines one, as SDL does) is pressed through the tree.
/// Mutation: delete the `role: .destructive` button.
@Test @MainActor func theShellGuideADrawnAlertIsPressedThroughTheTree() throws {
    let window = try harnessWindow(options: .init(presentsAlertsNatively: false)) { shellDeleteRoot() }
    try window.click(window.element(label: "Remove"))
    #expect(window.presentedAlert == nil)
    let delete = try #require(try window.elements { $0.role == .button && $0.label == "Delete" }.first)
    try window.click(delete)
    window.tick()
    _ = try window.element(label: "Deleted 1")
}

/// A file importer hears the path the user chose.
/// Mutation: delete the `.success` arm's `log.entries.append`.
@Test @MainActor func theShellGuideAnImporterHearsTheChosenFile() throws {
    let log = ShellLog()
    let window = try harnessWindow { shellImportRoot(log) }
    try window.click(window.element(label: "Import"))
    try window.respondToFileDialog(choosing: ["/tmp/a.json"])
    #expect(log.entries == ["chose /tmp/a.json"], "read \(log.entries)")
}

/// A right click opens the context menu and an item chosen by title runs.
/// Mutation: delete the `.contextMenu { … }`.
@Test @MainActor func theShellGuideAContextMenuItemRuns() throws {
    let log = ShellLog()
    let window = try harnessWindow { shellContextMenuRoot(log) }
    try window.rightClick(window.element(label: "Target"))
    let menu = try #require(window.presentedMenu)
    #expect(menu.items.map(\.title) == ["Copy"])
    try window.chooseMenuItem("Copy")
    #expect(log.entries == ["copy"], "read \(log.entries)")
}

/// A command declared on the app is in the menu bar and runs by path.
/// Mutation: delete the `app.commands { … }` call.
@Test @MainActor func theShellGuideACommandRunsFromTheMenuBar() throws {
    let log = ShellLog()
    let app = try TestApp(textSystem: harnessTextSystem)
    shellInstallCommands(app.app, log: log)
    _ = try app.openWindow(size: Size(width: Pixels(200), height: Pixels(100))) { Text("Body") }
    let tools = try #require(app.menuBar.first { $0.title == "Tools" })
    #expect(tools.items.map(\.title) == ["Run"])
    try app.performMenuBarItem("Tools", "Run")
    #expect(log.entries == ["run"], "read \(log.entries)")
}

/// The tree names the window, and the toolbar's item runs by id.
/// Mutation: delete `.navigationTitle("Notes")`.
@Test @MainActor func theShellGuideATreeTitlesTheWindowAndAToolbarItemRuns() throws {
    let log = ShellLog()
    let window = try harnessWindow { shellToolbarRoot(log) }
    #expect(window.platformWindow.title == "Notes")
    try window.performToolbarItem("add")
    #expect(log.entries == ["add"], "read \(log.entries)")
}

/// A document with unsaved changes vetoes a close; a clean one lets it go.
/// Mutation: make the handler answer `.now` whatever the document holds.
@Test @MainActor func theShellGuideADirtyDocumentVetoesTheCloseAndACleanOneDoesNot() throws {
    let document = ShellDocument()
    let window = try harnessWindow { Text("Doc") }
    shellGuardClose(window.window, document: document)
    document.hasUnsavedChanges = true
    #expect(window.requestClose() == false, "a dirty document stays open")
    #expect(!window.platformWindow.isClosed)
    document.hasUnsavedChanges = false
    #expect(window.requestClose() == true, "a clean one closes")
    #expect(window.platformWindow.isClosed)
}

// guide: drawing-and-gpu #1
import MetalUI

/// A diamond: four lines and a close.
struct DrawingDiamond: Shape {
    func path(in rect: Bounds<Pixels>) -> Path {
        Path { path in
            let width = rect.size.width.value, height = rect.size.height.value
            path.move(to: Point(x: Pixels(width / 2), y: Pixels(0)))
            path.addLine(to: Point(x: Pixels(width), y: Pixels(height / 2)))
            path.addLine(to: Point(x: Pixels(width / 2), y: Pixels(height)))
            path.addLine(to: Point(x: Pixels(0), y: Pixels(height / 2)))
            path.closeSubpath()
        }
    }
}

/// A gradient-filled diamond with a shadow below it.
@MainActor
func drawingBadgeRoot() -> some Element {
    VStack {
        DrawingDiamond()
            .fill(LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom))
            .frame(width: Pixels(60), height: Pixels(60))
            .shadow(color: .shadow, radius: Pixels(4), x: Pixels(0), y: Pixels(2))
    }
}
// end guide

// guide: drawing-and-gpu #2
/// Two squares that cast one shadow between them, not two.
@MainActor
func drawingGroupedRoot() -> some Element {
    VStack {
        HStack(spacing: Pixels(0)) {
            Rectangle().fill(Color.red).frame(width: Pixels(30), height: Pixels(30))
            Rectangle().fill(Color.blue).frame(width: Pixels(30), height: Pixels(30))
        }
        .compositingGroup()
        .shadow(radius: Pixels(4), x: Pixels(2), y: Pixels(2))
    }
}
// end guide

// guide: drawing-and-gpu #3
/// A gradient with a material panel over it.
@MainActor
func drawingMaterialRoot() -> some Element {
    VStack {
        ZStack {
            Rectangle().fill(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing))
            Color.clear.frame(width: Pixels(120), height: Pixels(40)).background(.regularMaterial)
        }
        .frame(width: Pixels(200), height: Pixels(120))
    }
}

/// The same panel under a shadow: the material degrades to its flat tint.
@MainActor
func drawingFlatMaterialRoot() -> some Element {
    VStack {
        Color.clear.frame(width: Pixels(120), height: Pixels(40))
            .background(.regularMaterial)
            .shadow(radius: Pixels(3), x: Pixels(2), y: Pixels(2))
    }
}
// end guide

// guide: drawing-and-gpu #4
/// A surface that redraws when `version` changes.
@MainActor
func drawingSurfaceRoot(version: Int) -> some Element {
    VStack {
        GPUSurface(redraw: .onDemand, value: version) { context in
            context.clear(red: 0.1, green: 0.2, blue: 0.4, alpha: 1)
        }
        .frame(width: Pixels(200), height: Pixels(120))
    }
}
// end guide

// guide: drawing-and-gpu #5
#if os(macOS)
import Metal

/// An app-owned Metal pass: clear the target, never commit.
@MainActor
func drawingMetalViewRoot() -> some Element {
    VStack {
        MetalView(redraw: .onDemand) { context in
            let pass = context.renderPassDescriptor(loadAction: .clear,
                                                    clearColor: MTLClearColor(red: 0, green: 0.4, blue: 0.2, alpha: 1))
            guard let encoder = context.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            encoder.endEncoding()
        }
        .frame(width: Pixels(200), height: Pixels(120))
    }
}
#endif
// end guide

// MARK: Drawing and GPU (T12)

/// **T12** — the drawing guide's roots build. Mutation: rename `drawingBadgeRoot`.
@Test @MainActor func theDrawingGuideBuildsInAHeadlessWindowAndItsClaimsHold() throws {
    _ = try harnessWindow { drawingBadgeRoot() }
    _ = try harnessWindow { drawingMaterialRoot() }
    _ = try harnessWindow { drawingFlatMaterialRoot() }
    _ = try harnessWindow { drawingGroupedRoot() }
    _ = try harnessWindow { drawingSurfaceRoot(version: 1) }
    #if os(macOS)
    _ = try harnessWindow { drawingMetalViewRoot() }
    #endif
}

/// A `Path` shape fills as one raster image. Mutation: delete the `.fill(…)`.
@Test @MainActor func theDrawingGuideAPathShapeDrawsAsOneImage() throws {
    let window = try harnessWindow(size: Size(width: Pixels(100), height: Pixels(100))) { drawingBadgeRoot() }
    #expect(window.scene.images.count >= 1, "read \(window.scene.images.count) images")
}

/// A material draws one backdrop record; under a shadow it draws a flat tint and none.
/// Mutation: delete `.background(.regularMaterial)` in either root.
@Test @MainActor func theDrawingGuideAMaterialIsOneBackdropAndDegradesUnderAShadow() throws {
    let real = try harnessWindow { drawingMaterialRoot() }
    #expect(real.scene.backdrops.count == 1, "read \(real.scene.backdrops.count)")
    let flat = try harnessWindow { drawingFlatMaterialRoot() }
    #expect(flat.scene.backdrops.isEmpty, "read \(flat.scene.backdrops.count)")
}

// guide: cross-platform #1
import MetalUI

/// A document type the file dialogs can filter by extension off Apple.
let crossAcceptedTypes: [ContentType] = [
    ContentType("com.example.notes", conformingTo: [.json], filenameExtensions: ["notes", "json"])
]

/// A button whose shortcut is the platform's primary modifier: Command on Apple, Control elsewhere.
@MainActor
func crossSaveRoot(_ log: ShellLog) -> some Element {
    VStack {
        Button("Save") { log.entries.append("save") }.keyboardShortcut("s")
    }
}
// end guide

// guide: cross-platform #2
/// A bitmap built from bytes is the same on every platform; a file may be missing.
@MainActor
func crossImageRoot() -> some Element {
    let bitmap = ImageBitmap(width: 4, height: 4, rgba: [UInt8](repeating: 255, count: 64))
    return VStack { Image(bitmap, scale: 1, label: Text("Logo")) }
}

/// A file path that is not there answers `nil`.
@MainActor
func crossLogo(path: String) -> ImageBitmap? {
    ImageBitmap(contentsOfFile: path)
}
// end guide

// MARK: Cross-platform (T13)

/// **T13** — the cross-platform guide's roots build. Mutation: rename `crossImageRoot`.
@Test @MainActor func theCrossPlatformGuideBuildsInAHeadlessWindowAndItsClaimsHold() throws {
    let window = try harnessWindow { crossImageRoot() }
    _ = try window.element(label: "Logo")
    _ = try harnessWindow { crossSaveRoot(ShellLog()) }
    #expect(crossAcceptedTypes.count == 1)
}

/// A path that is not there answers `nil`, never a trap. Mutation: make `crossLogo` return a bitmap.
@Test @MainActor func theCrossPlatformGuideAMissingFileIsNil() throws {
    #expect(crossLogo(path: "/nonexistent/guide-logo.png") == nil)
}

/// The primary modifier fires the shortcut on every platform: ⌘ on Apple, ⌃ elsewhere.
/// Mutation: change the shortcut key in the block.
@Test @MainActor func theCrossPlatformGuideThePrimaryModifierFiresTheShortcut() throws {
    let log = ShellLog()
    let window = try harnessWindow { crossSaveRoot(log) }
    window.typeKey("s")
    #expect(log.entries.isEmpty, "plain S is not a shortcut")
    window.typeKey("s", modifierFlags: .primary)
    #expect(log.entries == ["save"], "read \(log.entries)")
}

// MARK: Completeness (T14)

/// **T14** — `docs/guides/` holds exactly the six guides and the README lists each.
/// Mutation: remove a README row.
@Test func theGuideSetIsComplete() throws {
    let expected: Set<String> = ["layout", "state-and-identity", "input", "presentations-and-app-shell",
                                 "drawing-and-gpu", "cross-platform"]
    let guides = try GuideDocs.guides()
    #expect(Set(guides.map(\.name)) == expected, "read \(guides.map(\.name).sorted())")
    let readme = try GuideDocs.readme()
    for name in expected {
        #expect(readme.source.contains("](\(name).md"), "the README has no link to \(name).md")
    }
}
