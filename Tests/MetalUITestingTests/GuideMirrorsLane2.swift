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
    try window.click(window.element(label: "Delete"))
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
    try window.click(window.element(label: "Delete"))
    #expect(window.presentedAlert == nil)
    let delete = try #require(try window.elements { $0.role == .button && $0.label == "Delete" }.first)
    try window.click(delete)
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

// MARK: Drawing and GPU (T12)

/// **T12** — the drawing guide's roots build. Mutation: rename `drawingBadgeRoot`.
@Test @MainActor func theDrawingGuideBuildsInAHeadlessWindowAndItsClaimsHold() throws {
    _ = try harnessWindow { drawingBadgeRoot() }
    _ = try harnessWindow { drawingMaterialRoot() }
    _ = try harnessWindow { drawingFlatMaterialRoot() }
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

// MARK: Cross-platform (T13)

/// **T13** — the cross-platform guide's roots build. Mutation: rename `crossImageRoot`.
@Test @MainActor func theCrossPlatformGuideBuildsInAHeadlessWindowAndItsClaimsHold() throws {
    let window = try harnessWindow { crossImageRoot() }
    _ = try window.element(label: "Logo")
    _ = try harnessWindow { crossSaveRoot(ShellLog()) }
    #expect(crossAcceptedTypes.count == 1)
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
