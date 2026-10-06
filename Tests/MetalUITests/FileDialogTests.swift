import Testing
import Foundation
import Metal
import Observation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// The async file-dialog call and `ContentType`'s extensions, lane 2, tests
// 2.12–2.19 (rulings `SV-D`, `SV-E`, `SV-AD` item 2; spec §6.2). MetalUI-only:
// SwiftUI has no async panel call (gpui's `prompt_for_paths` is the comparison).
//
// **The bounded pattern** (spec §6.2): a test starts a `Task`, yields at most
// `psYieldBound` times until the fake recorded the call (`try #require`),
// delivers the answer through `onInput`, and reads the task's outcome from a
// box it fills — **never `await task.value`**, so a mutation that leaves the
// continuation unresumed fails the bound instead of hanging the run. Red
// before: the file does not compile at `3aa9898` (no `FileDialogs`).

/// What an awaiting task ended with.
@MainActor final class FDBox<Value> {
    var result: Result<Value, Error>?
}

let psYieldBound = 200

/// Yields until `condition` holds, at most `psYieldBound` times; whether it did.
@MainActor func fdYield(until condition: @MainActor () -> Bool) async -> Bool {
    var tries = 0
    while !condition() && tries < psYieldBound {
        await Task.yield()
        tries += 1
    }
    return condition()
}

/// Starts `body` in a main-actor task whose outcome lands in the box.
@MainActor func fdStart<Value>(_ body: @escaping @MainActor () async throws -> Value)
    -> (Task<Void, Never>, FDBox<Value>) {
    let box = FDBox<Value>()
    let task = Task { @MainActor in
        do { box.result = .success(try await body()) } catch { box.result = .failure(error) }
    }
    return (task, box)
}

// MARK: - 2.12–2.17: `FileDialogs`

/// **2.12** (`SV-D` items 1–2). `openFiles` presents an open dialog and returns
/// the chosen paths as file URLs; a cancelled one returns `[]`, not an error.
/// Mutation: throw on cancel.
@MainActor
@Test func fileDialogsOpenFilesReturnsTheURLsAndEmptyOnCancel() async throws {
    let (window, platform) = try psWindow { Column { psLeaf() } }
    window.drawFrameIfNeeded()
    let dialogs = window.fileDialogs

    let (task, box) = fdStart { try await dialogs.openFiles(allowedContentTypes: [.json],
                                                           allowsMultipleSelection: true) }
    defer { task.cancel() }
    try #require(await fdYield { !platform.presentedFileDialogs.isEmpty }, "the call must present")
    let dialog = platform.presentedFileDialogs[0]
    #expect(dialog.kind == .open(allowsMultipleSelection: true))
    #expect(dialog.allowedTypes == [psJSONType])
    psDeliver(platform, dialog.token, .chosen(["/tmp/k.json"]))
    try #require(await fdYield { box.result != nil }, "the awaiting task must resume")
    #expect(try box.result?.get() == [URL(fileURLWithPath: "/tmp/k.json")])

    let (again, cancelled) = fdStart { try await dialogs.openFiles(allowedContentTypes: [.json]) }
    defer { again.cancel() }
    try #require(await fdYield { platform.presentedFileDialogs.count == 2 })
    #expect(platform.presentedFileDialogs[1].kind == .open(allowsMultipleSelection: false))
    psDeliver(platform, platform.presentedFileDialogs[1].token, .cancelled)
    try #require(await fdYield { cancelled.result != nil })
    #expect(try cancelled.result?.get() == [], "a cancel is [] (SV-D item 2)")
    withExtendedLifetime(window) {}
}

/// **2.13** (`SV-D` item 2). `saveFile` presents a save dialog with the name
/// and types and returns `nil` on cancel, the URL on a choice. (2.12's
/// mutation site, named for the save half.)
@MainActor
@Test func fileDialogsSaveFileReturnsNilOnCancel() async throws {
    let (window, platform) = try psWindow { Column { psLeaf() } }
    window.drawFrameIfNeeded()
    let dialogs = window.fileDialogs

    let (task, box) = fdStart { try await dialogs.saveFile(contentTypes: [.json], defaultFilename: "theme") }
    defer { task.cancel() }
    try #require(await fdYield { !platform.presentedFileDialogs.isEmpty })
    let dialog = platform.presentedFileDialogs[0]
    #expect(dialog.kind == .save(defaultFilename: "theme"))
    #expect(dialog.allowedTypes == [psJSONType])
    psDeliver(platform, dialog.token, .cancelled)
    try #require(await fdYield { box.result != nil })
    #expect(try box.result?.get() == nil)

    let (again, chosen) = fdStart { try await dialogs.saveFile() }
    defer { again.cancel() }
    try #require(await fdYield { platform.presentedFileDialogs.count == 2 })
    #expect(platform.presentedFileDialogs[1].allowedTypes.isEmpty)
    psDeliver(platform, platform.presentedFileDialogs[1].token, .chosen(["/tmp/out.json"]))
    try #require(await fdYield { chosen.result != nil })
    #expect(try chosen.result?.get() == URL(fileURLWithPath: "/tmp/out.json"))
    withExtendedLifetime(window) {}
}

/// **2.14** (`SV-D` item 3). Cancelling the awaiting task dismisses the
/// dialog and throws `CancellationError`; a late answer for it runs nothing.
/// Mutation: no cancellation handler (the bound fails; the run does not hang).
@MainActor
@Test func cancellingTheAwaitingTaskDismissesAndThrows() async throws {
    let (window, platform) = try psWindow { Column { psLeaf() } }
    window.drawFrameIfNeeded()
    let dialogs = window.fileDialogs

    let (task, box) = fdStart { try await dialogs.openFiles(allowedContentTypes: [.json]) }
    try #require(await fdYield { !platform.presentedFileDialogs.isEmpty })
    let token = platform.presentedFileDialogs[0].token
    task.cancel()
    try #require(await fdYield { box.result != nil }, "a cancelled await must end")
    #expect(platform.dismissedPresentations == [token])
    #expect(throws: CancellationError.self) { try box.result?.get() }
    psDeliver(platform, token, .chosen(["/tmp/late.json"]))

    // The window is free again: a new call presents.
    let (next, nextBox) = fdStart { try await dialogs.openFiles(allowedContentTypes: []) }
    defer { next.cancel() }
    try #require(await fdYield { platform.presentedFileDialogs.count == 2 })
    psDeliver(platform, platform.presentedFileDialogs[1].token, .cancelled)
    try #require(await fdYield { nextBox.result != nil })
    #expect(try nextBox.result?.get() == [])
    withExtendedLifetime(window) {}
}

/// **2.15** (`SV-D` item 2). A second call while a dialog is up throws
/// `.busy` at once, and the first is unaffected. Mutation: queue it.
@MainActor
@Test func fileDialogsWhileBusyThrowsBusy() async throws {
    let (window, platform) = try psWindow { Column { psLeaf() } }
    window.drawFrameIfNeeded()
    let dialogs = window.fileDialogs

    let (task, box) = fdStart { try await dialogs.openFiles(allowedContentTypes: [.json]) }
    defer { task.cancel() }
    try #require(await fdYield { !platform.presentedFileDialogs.isEmpty })
    let (second, secondBox) = fdStart { try await dialogs.saveFile() }
    defer { second.cancel() }
    try #require(await fdYield { secondBox.result != nil }, "a busy call must answer at once")
    #expect(throws: FileDialogError.busy) { try secondBox.result?.get() }
    #expect(platform.presentedFileDialogs.count == 1)
    psDeliver(platform, platform.presentedFileDialogs[0].token, .chosen(["/tmp/a.json"]))
    try #require(await fdYield { box.result != nil })
    #expect(try box.result?.get() == [URL(fileURLWithPath: "/tmp/a.json")])
    withExtendedLifetime(window) {}
}

/// **2.16** (`SV-D` item 2). An unbound environment's `fileDialogs` and one
/// whose window is gone throw `.noWindow`; the value holds its window weakly,
/// so the window deinitialises while a copy is kept. Mutation: hold the window
/// strongly (it never deinitialises).
@MainActor
@Test func anUnboundOrDeadWindowThrowsNoWindow() async throws {
    let unbound = EnvironmentValues().fileDialogs
    await #expect(throws: FileDialogError.noWindow) {
        _ = try await unbound.openFiles(allowedContentTypes: [.json])
    }

    weak var weakWindow: Window?
    var kept: FileDialogs?
    do {
        let (window, _) = try psWindow { Column { psLeaf() } }
        window.drawFrameIfNeeded()
        kept = window.fileDialogs
        weakWindow = window
    }
    #expect(weakWindow == nil, "a FileDialogs value must not keep its window alive")
    let dialogs = try #require(kept)
    await #expect(throws: FileDialogError.noWindow) {
        _ = try await dialogs.saveFile()
    }
}

/// A component whose button starts an async open through the environment.
private struct FDOpener: Component {
    let box: FDBox<[URL]>
    @Environment(\.fileDialogs) var dialogs
    var content: some ElementGroup {
        // Read while building, as a SwiftUI `body` reads it.
        let dialogs = dialogs
        return Button("Open") {
            Task { @MainActor in
                do { box.result = .success(try await dialogs.openFiles(allowedContentTypes: [.json])) }
                catch { box.result = .failure(error) }
            }
        }
    }
}

/// **2.17** (`SV-D` items 1 and 4). `@Environment(\.fileDialogs)` read by a
/// `Button`'s action reaches the window's platform: the window stamps it.
/// Mutation: stamp nothing (the call throws `.noWindow`).
@MainActor
@Test func theEnvironmentCarriesTheWindowsFileDialogs() async throws {
    let box = FDBox<[URL]>()
    let (window, platform) = try psWindow { Column { FDOpener(box: box) } }
    window.recordsElementBounds = true
    window.drawFrameIfNeeded()
    let hit = try #require(window.lastHitboxes.first { $0.opaque }, "the button registers a target")
    let centre = Point(x: Pixels(hit.bounds.origin.x.value + hit.bounds.size.width.value / 2),
                       y: Pixels(hit.bounds.origin.y.value + hit.bounds.size.height.value / 2))
    platform.simulateInput(.mouseDown(MouseEvent(position: centre)))
    platform.simulateInput(.mouseUp(MouseEvent(position: centre)))
    let presented = await fdYield { !platform.presentedFileDialogs.isEmpty || box.result != nil }
    try #require(presented)
    try #require(platform.presentedFileDialogs.count == 1,
                 "the environment's value must reach the fake: \(String(describing: box.result))")
    psDeliver(platform, platform.presentedFileDialogs[0].token, .chosen(["/tmp/e.json"]))
    try #require(await fdYield { box.result != nil })
    #expect(try box.result?.get() == [URL(fileURLWithPath: "/tmp/e.json")])
    withExtendedLifetime(window) {}
}

// MARK: - 2.18–2.19: `ContentType`

/// **2.18** (`SV-E`). `.json` conforms to `.text` (and so `.data`, `.item`)
/// and is named `json`; `.plainText` is `txt`; `.utf8PlainText` inherits no
/// extension; drag and drop's matching is unchanged. Mutation: drop `.text`
/// from `.json`'s parents.
@Test func contentTypeJSONConformsToTextAndCarriesItsExtension() {
    #expect(ContentType.json.identifier == "public.json")
    #expect(ContentType.json.conforms(to: .text))
    #expect(ContentType.json.conforms(to: .data) && ContentType.json.conforms(to: .item))
    #expect(!ContentType.json.conforms(to: .plainText))
    #expect(ContentType.json.preferredFilenameExtension == "json")
    #expect(ContentType.plainText.preferredFilenameExtension == "txt")
    #expect(ContentType.utf8PlainText.preferredFilenameExtension == nil)
    #expect(ContentType.data.preferredFilenameExtension == nil)
    let custom = ContentType("com.example.keymap", conformingTo: [.json], filenameExtensions: ["keymap", "km"])
    #expect(custom.preferredFilenameExtension == "keymap")
    #expect(custom.conforms(to: .text))
    // Drag and drop's matching: a String still exports as utf8PlainText,
    // which conforms to plainText and text but not json.
    #expect("a".exportedContentTypes() == [.utf8PlainText])
    #expect(ContentType.utf8PlainText.conforms(to: .text) && !ContentType.utf8PlainText.conforms(to: .json))
}

/// **2.19** (`SV-E`). A `ContentType` reaches the seam as its identifier,
/// its transitive conformance sorted, and its extensions as declared.
/// Mutation: sort the conformance differently.
@Test func aPlatformFileTypeCarriesIdentifierConformanceAndExtensions() {
    #expect(ContentType.json.platformFileType == psJSONType)
    #expect(ContentType.plainText.platformFileType
            == PlatformFileType(identifier: "public.plain-text",
                                conformsTo: ["public.data", "public.item", "public.text"],
                                filenameExtensions: ["txt"]))
    let custom = ContentType("com.example.keymap", conformingTo: [.json], filenameExtensions: ["keymap", "km"])
    #expect(custom.platformFileType.conformsTo == ["public.data", "public.item", "public.json", "public.text"])
    #expect(custom.platformFileType.filenameExtensions == ["keymap", "km"])
}
