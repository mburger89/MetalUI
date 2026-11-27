import Testing
import Foundation
import MetalUICore
import MetalUIPlatform
import MetalUITesting
@testable import MetalUI
@testable import MetalUIAppKit

// The file dialog's starting directory (ruling `SV-AQ`, record 432):
// `.fileDialogDefaultDirectory(_:)` for the importer and exporter, a
// `directory:` argument for `FileDialogs`. SwiftUI's modifier is
// `fileDialogDefaultDirectory(_ defaultDirectory: URL?)` (macOS 15).

private let projectURL = URL(fileURLWithPath: "/tmp/metalui-project", isDirectory: true)

/// **D1** (`SV-AQ` item 1). `.fileDialogDefaultDirectory(_:)` written above an
/// importer and an exporter reaches the dialog's `directory`; written on the
/// content inside it, `nil`, a non-file URL, or no modifier at all, the
/// dialog's is `nil`; the nearest writer wins.
///
/// Mutations **MD1a**: `PlatformFileDialog.init` drops `directory`; **MD1b**:
/// `present` sends `directory: nil`; **MD1c**: `notePresentation` reads the
/// window's root environment; **MD1d**: `platformDirectoryPath` accepts a
/// non-file URL.
@MainActor
@Test func theDefaultDirectoryModifierReachesTheImporterAndTheExporter() throws {
    let importer = PSModel()
    importer.shown = true
    let (window, platform) = try psWindow {
        Column {
            psLeaf().fileImporter(isPresented: importer.binding, allowedContentTypes: [.json]) { _ in }
                .fileDialogDefaultDirectory(projectURL)
                .fileDialogDefaultDirectory(URL(fileURLWithPath: "/tmp/far"))
        }
    }
    window.drawFrameIfNeeded()
    #expect(platform.presentedFileDialogs.first?.directory == "/tmp/metalui-project")

    let exporter = PSModel()
    exporter.shown = true
    let (exportWindow, exportPlatform) = try psWindow {
        Column {
            psLeaf().fileExporter(isPresented: exporter.binding, item: Data("{}".utf8), contentTypes: [.json],
                                  defaultFilename: "k", onCompletion: { _ in })
                .fileDialogDefaultDirectory(projectURL)
        }
    }
    exportWindow.drawFrameIfNeeded()
    #expect(exportPlatform.presentedFileDialogs.first?.directory == "/tmp/metalui-project")

    let cases: [(String, URL?)] = [("nil", nil), ("a web URL", URL(string: "https://example.com/a")!)]
    for (name, url) in cases {
        let model = PSModel()
        model.shown = true
        let (w, p) = try psWindow {
            Column {
                psLeaf().fileImporter(isPresented: model.binding, allowedContentTypes: [.json]) { _ in }
                    .fileDialogDefaultDirectory(url)
            }
        }
        w.drawFrameIfNeeded()
        #expect(p.presentedFileDialogs.first != nil && p.presentedFileDialogs.first?.directory == nil, "\(name)")
        withExtendedLifetime(w) {}
    }

    let inside = PSModel()
    inside.shown = true
    let (innerWindow, innerPlatform) = try psWindow {
        Column {
            psLeaf().fileDialogDefaultDirectory(projectURL)
                .fileImporter(isPresented: inside.binding, allowedContentTypes: [.json]) { _ in }
        }
    }
    innerWindow.drawFrameIfNeeded()
    #expect(innerPlatform.presentedFileDialogs.first != nil)
    #expect(innerPlatform.presentedFileDialogs.first?.directory == nil, "inside the presenter is not above it")

    let plain = PSModel()
    plain.shown = true
    let (plainWindow, plainPlatform) = try psWindow {
        Column { psLeaf().fileImporter(isPresented: plain.binding, allowedContentTypes: [.json]) { _ in } }
    }
    plainWindow.drawFrameIfNeeded()
    #expect(plainPlatform.presentedFileDialogs.first != nil && plainPlatform.presentedFileDialogs.first?.directory == nil)
    withExtendedLifetime((window, exportWindow, innerWindow, plainWindow)) {}
}

/// **D2** (`SV-AQ` item 2). `openFiles(…directory:)` and `saveFile(…directory:)`
/// send the directory; no argument, `nil` and a non-file URL send `nil`.
///
/// Mutation **MD2**: `runFileDialog` builds the request without `directory`.
@MainActor
@Test func theDirectoryArgumentReachesTheOpenAndSaveRequests() async throws {
    let (window, platform) = try psWindow { Column { psLeaf() } }
    window.drawFrameIfNeeded()
    let dialogs = window.fileDialogs
    let arguments: [(URL?, String?)] = [
        (projectURL, "/tmp/metalui-project"), (nil, nil), (URL(string: "https://example.com/a")!, nil)
    ]
    for (url, expected) in arguments {
        for save in [false, true] {
            let before = platform.presentedFileDialogs.count
            let (task, _) = save
                ? fdStart { _ = try await dialogs.saveFile(contentTypes: [.json], defaultFilename: "a", directory: url) }
                : fdStart { _ = try await dialogs.openFiles(allowedContentTypes: [.json], directory: url) }
            try #require(await fdYield { platform.presentedFileDialogs.count > before })
            let dialog = platform.presentedFileDialogs[before]
            #expect(dialog.directory == expected, "\(String(describing: url)) save: \(save)")
            psDeliver(platform, dialog.token, .cancelled)
            await task.value
        }
    }
    let before = platform.presentedFileDialogs.count
    let (task, _) = fdStart { _ = try await dialogs.openFiles(allowedContentTypes: []) }
    try #require(await fdYield { platform.presentedFileDialogs.count > before })
    #expect(platform.presentedFileDialogs[before].directory == nil, "no argument: the system's")
    psDeliver(platform, platform.presentedFileDialogs[before].token, .cancelled)
    await task.value
    withExtendedLifetime(window) {}
}

/// **D3** (`SV-AQ` item 3). AppKit's panel starts in the seam's directory — a
/// directory file URL — and in none when the seam names none; read without a
/// panel, whose initialiser does not return under a locked screen.
///
/// Mutation **MD3**: `directoryURL` answers `nil`.
@Test func theAppKitPanelStartsInTheSeamsDirectory() {
    let open = PlatformFileDialog(token: 1, kind: .open(allowsMultipleSelection: false),
                                  directory: "/tmp/metalui-project")
    #expect(AppKitWindow.directoryURL(open) == projectURL)
    #expect(AppKitWindow.directoryURL(open)?.hasDirectoryPath == true)
    #expect(AppKitWindow.directoryURL(PlatformFileDialog(token: 1, kind: .save(defaultFilename: "a"))) == nil)
}

/// **D4** (`SV-AQ` item 1). The environment value costs an idle window no
/// element request: a steady frame under a closed importer has the same
/// `elementRequests` with the modifier written as without it. (Allocations: the
/// value is read only when a scope notes a presentation, so a window with no
/// dialog never touches it; the repo's steady-frame allocation pins, e.g.
/// `aNonAnimatableComponentAllocatesWhatItDid`, stay at their values.)
@MainActor
@Test func theDefaultDirectoryCostsAnIdleFrameNoRequests() throws {
    func idleRequests(directory: URL?) throws -> Int {
        let model = PSModel()
        let w = try TestWindow(size: Size(width: Pixels(200), height: Pixels(200))) {
            Column {
                psLeaf().fileImporter(isPresented: model.binding, allowedContentTypes: [.json]) { _ in }
                    .fileDialogDefaultDirectory(directory)
            }
        }
        defer { withExtendedLifetime(w) {} }
        for _ in 0..<3 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
        return w.lastFrameWork.elementRequests
    }
    #expect(try idleRequests(directory: projectURL) == idleRequests(directory: nil))
}
