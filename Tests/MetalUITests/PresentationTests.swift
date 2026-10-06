import Testing
import Foundation
import Metal
import Observation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Presentations and the file-dialog modifiers, lane 2, tests 2.1–2.11 (rulings
// `SV-C`, `SV-K`; spec `docs/superpowers/specs/2026-10-04-platform-services-design.md`
// §6.2). SwiftUI's side is `docs/probes/swiftui-platform-services.swift`, arms
// `D1`–`D5` (importer) and `X1`–`X5` (exporter), named per test.
//
// Every test drives a `Window` over `FakePlatformWindow`: `presentFileDialog`
// is recorded and answers `presentsFileDialogs` (default `true`), and a test
// delivers the platform's answer with `simulateInput(.fileDialogResult(…))` —
// as AppKit and SDL queue it, after the presenting call returned. Nothing
// sleeps. Red before, for every test here: the file does not compile at
// `3aa9898` (no `fileImporter`, `fileExporter` or `PresentationScope`).

// MARK: - Harness

/// The `isPresented` source every tree binds, logging each write, and the
/// callbacks' log.
@Observable @MainActor final class PSModel {
    var shown = false
    var second = false
    var log: [String] = []
    var owner: GlobalElementID?
    var errors: [FileDialogError] = []

    var binding: Binding<Bool> {
        Binding(get: { self.shown }, set: { self.shown = $0; self.log.append("isPresented=\($0)") })
    }
    var secondBinding: Binding<Bool> {
        Binding(get: { self.second }, set: { self.second = $0; self.log.append("second=\($0)") })
    }
}

@MainActor func psLeaf() -> some StyledElement {
    Box().frame(width: Pixels(10), height: Pixels(10)).background(.accent)
}

@MainActor func psWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    try makeFakeWindowOnDefaultDevice(size: 200, content: content)
}

@MainActor func psRedraw(_ window: Window) {
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
}

let psRoot = GlobalElementID.child(of: nil, at: 0, name: nil)
/// The position of the scope on the first child of a `Column` root — the
/// owner a presentation's outcome is dispatched to (`SV-K` item 2).
let psOwner = GlobalElementID.child(of: psRoot, at: 0, name: nil)

/// `public.json` at the seam: `.json`'s transitive conformance, sorted (`SV-E`).
let psJSONType = PlatformFileType(identifier: "public.json",
                                  conformsTo: ["public.data", "public.item", "public.text"],
                                  filenameExtensions: ["json"])

@MainActor func psDeliver(_ platform: FakePlatformWindow, _ token: Int,
                          _ outcome: FileDialogResultEvent.Outcome) {
    platform.simulateInput(.fileDialogResult(FileDialogResultEvent(token: token, outcome: outcome)))
}

/// A two-representation `Transferable` (test 2.8): plain text first, JSON
/// second, with distinguishable bytes.
struct PSNote: MetalUI.Transferable {
    func exportedContentTypes() -> [ContentType] { [.plainText, .json] }
    static func importedContentTypes() -> [ContentType] { [.plainText] }
    func exported(as contentType: ContentType) -> Data? {
        if ContentType.json.conforms(to: contentType) { return Data("{\"n\":1}".utf8) }
        if ContentType.plainText.conforms(to: contentType) { return Data("n=1".utf8) }
        return nil
    }
    init?(importing data: Data, contentType: ContentType) { return nil }
    init() {}
}

/// A fresh directory for an exporter's writes.
func psTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("metalui-presentations-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - 2.1–2.6: the importer

/// **2.1** (`SV-K` item 3, `D1`, `D5`). `isPresented` true presents after the
/// frame — nothing before it — once: one `.open(allowsMultipleSelection:
/// true)` request with `[json]`'s seam type and the platform's own title and
/// prompt; the next three frames present nothing more while it is up.
/// Mutation: drop the in-flight check (each frame re-presents).
@MainActor
@Test func anImporterPresentsAfterTheFrameOnceWhileShown() throws {
    let m = PSModel()
    m.shown = true
    let (window, platform) = try psWindow {
        Column {
            psLeaf().fileImporter(isPresented: m.binding, allowedContentTypes: [.json],
                                  allowsMultipleSelection: true) { _ in m.log.append("completion") }
        }
    }
    #expect(platform.presentedFileDialogs.isEmpty, "nothing presents before the first frame")
    window.drawFrameIfNeeded()
    let dialog = try #require(platform.presentedFileDialogs.first, "the first frame presents")
    #expect(platform.presentedFileDialogs.count == 1)
    #expect(dialog.kind == .open(allowsMultipleSelection: true))
    #expect(dialog.allowedTypes == [psJSONType])
    #expect(dialog.title == nil && dialog.prompt == nil, "the platform's own title and prompt (D1)")
    for _ in 0..<3 { psRedraw(window) }
    #expect(platform.presentedFileDialogs.count == 1, "presented once while it is up (D5)")
    #expect(m.log.isEmpty)
    withExtendedLifetime(window) {}
}

/// **2.2** (`SV-C` item 3). A chosen import writes `isPresented = false`
/// first, then completes with the platform's paths as file URLs — from input,
/// dispatched to the declaring element (`StateDispatch.owner` is the scope's
/// position). Mutations: swap the order; run outside `StateDispatch` (the
/// owner reads `nil`).
@MainActor
@Test func aChosenImportWritesIsPresentedFalseThenCompletesWithURLs() throws {
    let m = PSModel()
    m.shown = true
    var urls: [URL] = []
    let (window, platform) = try psWindow {
        Column {
            psLeaf().fileImporter(isPresented: m.binding, allowedContentTypes: [.json],
                                  allowsMultipleSelection: true) { result in
                m.log.append("completion")
                m.owner = StateDispatch.owner
                urls = (try? result.get()) ?? []
            }
        }
    }
    window.drawFrameIfNeeded()
    let dialog = try #require(platform.presentedFileDialogs.first)
    psDeliver(platform, dialog.token, .chosen(["/tmp/a.json", "/tmp/b c.json"]))
    #expect(m.log == ["isPresented=false", "completion"])
    #expect(urls == [URL(fileURLWithPath: "/tmp/a.json"), URL(fileURLWithPath: "/tmp/b c.json")])
    #expect(urls.allSatisfy { $0.isFileURL })
    #expect(m.owner == psOwner, "dispatched to the declaring position: \(String(describing: m.owner))")
    withExtendedLifetime(window) {}
}

/// **2.3** (`D2`, `D4`). A cancelled import calls nothing and writes
/// `isPresented = false`. Mutation: call `onCompletion(.failure)` on cancel.
@MainActor
@Test func aCancelledImportCallsNothingAndWritesIsPresentedFalse() throws {
    let m = PSModel()
    m.shown = true
    let (window, platform) = try psWindow {
        Column {
            psLeaf().fileImporter(isPresented: m.binding, allowedContentTypes: [.json],
                                  allowsMultipleSelection: false) { _ in m.log.append("completion") }
        }
    }
    window.drawFrameIfNeeded()
    let dialog = try #require(platform.presentedFileDialogs.first)
    psDeliver(platform, dialog.token, .cancelled)
    #expect(m.log == ["isPresented=false"])
    #expect(m.shown == false)
    withExtendedLifetime(window) {}
}

/// **2.4** (`D3`, `SV-K` item 3). `isPresented` set `false` while the dialog
/// is up dismisses it after the next frame (`dismissPresentation(token:)`), and
/// a late answer for that token — SDL cannot close its dialog — runs nothing.
/// Mutation: not forgetting the token (the late answer completes).
@MainActor
@Test func isPresentedFalseDismissesAndALateResultRunsNothing() throws {
    let m = PSModel()
    m.shown = true
    let (window, platform) = try psWindow {
        Column {
            psLeaf().fileImporter(isPresented: m.binding, allowedContentTypes: [.json],
                                  allowsMultipleSelection: false) { _ in m.log.append("completion") }
        }
    }
    window.drawFrameIfNeeded()
    let dialog = try #require(platform.presentedFileDialogs.first)
    m.shown = false
    window.drawFrameIfNeeded()
    #expect(platform.dismissedPresentations == [dialog.token])
    psDeliver(platform, dialog.token, .chosen(["/tmp/late.json"]))
    #expect(m.log.isEmpty, "a late answer runs nothing: \(m.log)")
    psRedraw(window)
    #expect(platform.presentedFileDialogs.count == 1 && platform.dismissedPresentations.count == 1)
    withExtendedLifetime(window) {}
}

/// **2.4b** (`SV-G` item 5, review fix). A stale answer never reaches the
/// request in flight after it: dialog A is dismissed, dialog B is presented,
/// and A's late answer — SDL cannot close A — leaves B in flight with nothing
/// run; B's own answer then lands. Mutation `P5`: drop `inFlight.token ==
/// result.token` from `handleFileDialogResult` (A's answer completes B).
@MainActor
@Test func aStaleDialogAnswerNeverReachesTheNextRequest() throws {
    let m = PSModel()
    m.shown = true
    let (window, platform) = try psWindow {
        Column {
            psLeaf().fileImporter(isPresented: m.binding, allowedContentTypes: [.json],
                                  allowsMultipleSelection: false) { _ in m.log.append("completion") }
        }
    }
    window.drawFrameIfNeeded()
    let a = try #require(platform.presentedFileDialogs.first)
    m.shown = false
    window.drawFrameIfNeeded()
    try #require(platform.dismissedPresentations == [a.token])
    m.shown = true
    window.drawFrameIfNeeded()
    try #require(platform.presentedFileDialogs.count == 2)
    let b = platform.presentedFileDialogs[1]
    try #require(b.token != a.token)
    psDeliver(platform, a.token, .chosen(["/tmp/stale.json"]))
    #expect(m.log.isEmpty, "A's answer runs nothing: \(m.log)")
    #expect(m.shown == true)
    #expect(window.presentations.inFlight?.token == b.token, "B is still in flight")
    psDeliver(platform, b.token, .chosen(["/tmp/b.json"]))
    #expect(m.log == ["isPresented=false", "completion"])
    #expect(window.presentations.inFlight == nil)
    withExtendedLifetime(window) {}
}

/// 2.5's tree: an importer logging its failures into the model.
@MainActor func psFailureTree(_ m: PSModel) -> some Element {
    Column {
        psLeaf().fileImporter(isPresented: m.binding, allowedContentTypes: [.json],
                              allowsMultipleSelection: false) { result in
            m.log.append("completion")
            if case .failure(let error) = result, let error = error as? FileDialogError { m.errors.append(error) }
        }
    }
}

/// **2.5** (`SV-C` item 3). A platform failure completes with
/// `FileDialogError.platform(message)`; a platform that cannot show one
/// (`presentFileDialog` → `false`) completes with `.unavailable` after the
/// frame; both write `isPresented = false` first. Mutation: swallow the
/// failure.
@MainActor
@Test func aFailedOrUnavailableDialogCompletesWithFailure() throws {
    let m = PSModel()
    m.shown = true
    let (window, platform) = try psWindow { psFailureTree(m) }
    window.drawFrameIfNeeded()
    let dialog = try #require(platform.presentedFileDialogs.first)
    psDeliver(platform, dialog.token, .failed("x"))
    #expect(m.log == ["isPresented=false", "completion"])
    #expect(m.errors == [.platform("x")])

    m.log = []
    m.errors = []
    m.shown = true
    let (other, otherPlatform) = try psWindow { psFailureTree(m) }
    otherPlatform.presentsFileDialogs = false
    other.drawFrameIfNeeded()
    #expect(otherPlatform.presentedFileDialogs.count == 1, "asked once")
    #expect(m.log == ["isPresented=false", "completion"])
    #expect(m.errors == [.unavailable])
    withExtendedLifetime((window, other)) {}
}

/// **2.6** (`SV-C` item 3). The single-URL importer asks for one file and
/// completes with the first path. Mutation: pass the last.
@MainActor
@Test func theSingleURLImporterPassesTheFirstURL() throws {
    let m = PSModel()
    m.shown = true
    var chosen: URL?
    let (window, platform) = try psWindow {
        Column {
            psLeaf().fileImporter(isPresented: m.binding, allowedContentTypes: [.json, .plainText]) { result in
                chosen = try? result.get()
            }
        }
    }
    window.drawFrameIfNeeded()
    let dialog = try #require(platform.presentedFileDialogs.first)
    #expect(dialog.kind == .open(allowsMultipleSelection: false))
    #expect(dialog.allowedTypes.map(\.identifier) == ["public.json", "public.plain-text"])
    psDeliver(platform, dialog.token, .chosen(["/tmp/first.json", "/tmp/second.json"]))
    #expect(chosen == URL(fileURLWithPath: "/tmp/first.json"))
    withExtendedLifetime(window) {}
}

// MARK: - 2.7–2.10: the exporter

/// **2.7** (`SV-C` items 2 and 4, `X1`). An exporter of `Data` as `.json`
/// asks for a save dialog named `defaultFilename`, titled and prompted
/// "Export", and on a chosen path writes the item's bytes there, then
/// completes with the URL; `isPresented` is `false` first. Mutation: write only
/// `exported(as: chosen)` (`nil` for `Data` as `.json` → a failure).
@MainActor
@Test func anExporterWritesTheItemsBytesAndCompletesWithTheURL() throws {
    let m = PSModel()
    m.shown = true
    let directory = try psTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let bytes = Data("{\"keys\":[1,2,3]}".utf8)
    var outcome: Result<URL, Error>?
    let (window, platform) = try psWindow {
        Column {
            psLeaf().fileExporter(isPresented: m.binding, item: bytes, contentTypes: [.json],
                                  defaultFilename: "keymap") { result in
                m.log.append("completion")
                outcome = result
            } onCancellation: {
                m.log.append("cancelled")
            }
        }
    }
    window.drawFrameIfNeeded()
    let dialog = try #require(platform.presentedFileDialogs.first)
    #expect(dialog.kind == .save(defaultFilename: "keymap"))
    #expect(dialog.allowedTypes == [psJSONType])
    #expect(dialog.title == "Export" && dialog.prompt == "Export", "X1")
    let target = directory.appendingPathComponent("keymap.json")
    psDeliver(platform, dialog.token, .chosen([target.path]))
    #expect(m.log == ["isPresented=false", "completion"])
    let url = try #require(try outcome?.get(), "the export must succeed: \(String(describing: outcome))")
    #expect(url == target)
    #expect(try Data(contentsOf: target) == bytes)
    withExtendedLifetime(window) {}
}

/// **2.8** (`SV-C` item 4). An item with two representations writes the one
/// conforming to the chosen content type, not its first. Mutation: always the
/// first.
@MainActor
@Test func anExporterPrefersAConformingRepresentation() throws {
    let m = PSModel()
    m.shown = true
    let directory = try psTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let (window, platform) = try psWindow {
        Column {
            psLeaf().fileExporter(isPresented: m.binding, item: PSNote(), contentTypes: [.json]) { _ in
                m.log.append("completion")
            }
        }
    }
    window.drawFrameIfNeeded()
    let dialog = try #require(platform.presentedFileDialogs.first)
    #expect(dialog.kind == .save(defaultFilename: nil))
    let target = directory.appendingPathComponent("note.json")
    psDeliver(platform, dialog.token, .chosen([target.path]))
    #expect(String(decoding: try Data(contentsOf: target), as: UTF8.self) == "{\"n\":1}")
    withExtendedLifetime(window) {}
}

/// **2.9** (`X3`, `X4`). A cancelled export calls `onCancellation` once and no
/// completion; `isPresented` is `false` first. Mutation: call the completion.
@MainActor
@Test func aCancelledExportCallsOnCancellation() throws {
    let m = PSModel()
    m.shown = true
    let (window, platform) = try psWindow {
        Column {
            psLeaf().fileExporter(isPresented: m.binding, item: "notes", contentTypes: [.plainText],
                                  defaultFilename: "notes") { _ in
                m.log.append("completion")
            } onCancellation: {
                m.log.append("cancelled")
            }
        }
    }
    window.drawFrameIfNeeded()
    let dialog = try #require(platform.presentedFileDialogs.first)
    psDeliver(platform, dialog.token, .cancelled)
    #expect(m.log == ["isPresented=false", "cancelled"])
    withExtendedLifetime(window) {}
}

/// **2.10** (`X5`). An exporter whose item is `nil` still presents; a chosen
/// path completes with `FileExportError.noItem` and writes nothing. Mutation:
/// skip presenting for `nil`.
@MainActor
@Test func aNilItemExporterPresentsAndFailsOnConfirm() throws {
    let m = PSModel()
    m.shown = true
    let directory = try psTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    var failure: FileExportError?
    let (window, platform) = try psWindow {
        Column {
            psLeaf().fileExporter(isPresented: m.binding, item: nil as Data?, contentTypes: [.json]) { result in
                if case .failure(let error) = result { failure = error as? FileExportError }
            }
        }
    }
    window.drawFrameIfNeeded()
    let dialog = try #require(platform.presentedFileDialogs.first, "a nil item still presents (X5)")
    let target = directory.appendingPathComponent("nothing.json")
    psDeliver(platform, dialog.token, .chosen([target.path]))
    #expect(failure == .noItem)
    #expect(!FileManager.default.fileExists(atPath: target.path))
    #expect(m.shown == false)
    withExtendedLifetime(window) {}
}

// MARK: - 2.11: one at a time

/// **2.11** (`SV-K` item 3). Two presentations shown at once wait their turn:
/// the second presents only after the first's answer, on the next frame.
/// Mutation: present both.
@MainActor
@Test func twoPresentationsWaitTheirTurn() throws {
    let m = PSModel()
    m.shown = true
    m.second = true
    let (window, platform) = try psWindow {
        Column {
            psLeaf().fileImporter(isPresented: m.binding, allowedContentTypes: [.json],
                                  allowsMultipleSelection: false) { _ in m.log.append("first") }
            psLeaf().fileExporter(isPresented: m.secondBinding, item: Data(), contentTypes: [.json]) { _ in
                m.log.append("second")
            }
        }
    }
    window.drawFrameIfNeeded()
    psRedraw(window)
    try #require(platform.presentedFileDialogs.count == 1, "one at a time: \(platform.presentedFileDialogs)")
    let first = platform.presentedFileDialogs[0]
    #expect(first.kind == .open(allowsMultipleSelection: false))
    psDeliver(platform, first.token, .cancelled)
    #expect(platform.presentedFileDialogs.count == 1, "the next waits for a frame")
    window.drawFrameIfNeeded()
    try #require(platform.presentedFileDialogs.count == 2)
    let second = platform.presentedFileDialogs[1]
    #expect(second.kind == .save(defaultFilename: nil))
    #expect(second.token != first.token, "tokens are unique per request")
    withExtendedLifetime(window) {}
}
