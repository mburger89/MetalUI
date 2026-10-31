import Testing
import Foundation
import UniformTypeIdentifiers
import MetalUICore
import MetalUIPlatform
@testable import MetalUI
@testable import MetalUIAppKit

// A `.fileImporter` that chooses folders (ruling `SV-AM`, amending `SV-F`'s
// files only; record 170). `ContentType.folder`/`.directory` mirror UTType's;
// the seam reads a directory type off `allowedTypes`
// (`PlatformFileDialog.canChooseDirectories`/`canChooseFiles`); the AppKit
// panel's configuration is read without an `NSOpenPanel`, whose initialiser
// does not return under a locked screen; a folder-only importer completes with
// directory URLs. Red before: the file does not compile at d2797c5d (no
// `.folder`, no `canChooseDirectories`, no `openPanelConfiguration`).

/// **F1** (`SV-AM` item 1). `.folder` conforms to `.directory` and `.item`,
/// `.directory` to `.item` alone — neither to `.data` — as UTType's do,
/// measured here against the system's types.
///
/// Mutation **MF1**: declare `.folder` `conformingTo: [.item]` (drops
/// `.directory`).
@Test func folderAndDirectoryConformAsUTTypesDo() {
    #expect(ContentType.folder.identifier == UTType.folder.identifier)
    #expect(ContentType.directory.identifier == UTType.directory.identifier)
    #expect(ContentType.folder.conforms(to: .directory) == UTType.folder.conforms(to: .directory))
    #expect(ContentType.folder.conforms(to: .directory))
    #expect(ContentType.folder.conforms(to: .item))
    #expect(!ContentType.folder.conforms(to: .data) && !UTType.folder.conforms(to: .data))
    #expect(ContentType.directory.conforms(to: .item))
    #expect(!ContentType.directory.conforms(to: .data) && !UTType.directory.conforms(to: .data))
    #expect(!ContentType.directory.conforms(to: .folder))
}

/// The seam's open dialog over `types`.
private func openDialog(_ types: [ContentType], multiple: Bool = false) -> PlatformFileDialog {
    PlatformFileDialog(token: 1, kind: .open(allowsMultipleSelection: multiple),
                       allowedTypes: types.map(\.platformFileType))
}

/// **F2** (`SV-AM` item 2). A directory type — `.folder` by its conformance,
/// `.directory` by its identifier — makes an open dialog choose directories;
/// alone it chooses no files; beside a file type both. An empty list,
/// `.item`, a file type and every save dialog choose files only (the
/// pre-`SV-AM` default, unchanged).
///
/// Mutations **MF2a**: `isDirectory` reads the identifier alone (drops
/// `conformsTo`); **MF2b**: `canChooseFiles` always `true`; **MF2c**:
/// `canChooseDirectories` always `false`.
@Test func theSeamReadsADirectoryTypeAsChoosingDirectories() {
    let folder = openDialog([.folder])
    #expect(folder.canChooseDirectories && !folder.canChooseFiles)
    let directory = openDialog([.directory])
    #expect(directory.canChooseDirectories && !directory.canChooseFiles)
    let mixed = openDialog([.folder, .json])
    #expect(mixed.canChooseDirectories && mixed.canChooseFiles)
    for files in [openDialog([]), openDialog([.item]), openDialog([.json]), openDialog([.data])] {
        #expect(files.canChooseFiles && !files.canChooseDirectories, "\(files.allowedTypes.map(\.identifier))")
    }
    let save = PlatformFileDialog(token: 2, kind: .save(defaultFilename: nil),
                                  allowedTypes: [ContentType.folder.platformFileType])
    #expect(save.canChooseFiles && !save.canChooseDirectories, "a save dialog never chooses a directory")
    #expect(ContentType.choosesDirectoriesOnly([.folder]) && !ContentType.choosesDirectoriesOnly([.folder, .json]))
    #expect(!ContentType.choosesDirectoriesOnly([]))
}

/// **F3** (`SV-AM` item 3). AppKit's open panel for `[.folder]` chooses
/// directories and no files and keeps `UTType.folder` in its content types;
/// `[.folder, .json]` chooses both; `[.json]` and `[]` files only — `SV-F`'s
/// configuration, unchanged.
///
/// Mutation **MF3**: `openPanelConfiguration` answers `SV-F`'s constant
/// `(true, false, …)`.
@Test func theOpenPanelChoosesFoldersForAFolderType() {
    let folder = AppKitWindow.openPanelConfiguration(openDialog([.folder]))
    #expect(folder.canChooseDirectories && !folder.canChooseFiles)
    #expect(folder.allowedContentTypes == [UTType.folder])
    let mixed = AppKitWindow.openPanelConfiguration(openDialog([.folder, .json]))
    #expect(mixed.canChooseDirectories && mixed.canChooseFiles)
    #expect(mixed.allowedContentTypes == [UTType.folder, UTType.json])
    let json = AppKitWindow.openPanelConfiguration(openDialog([.json]))
    #expect(json.canChooseFiles && !json.canChooseDirectories && json.allowedContentTypes == [UTType.json])
    let any = AppKitWindow.openPanelConfiguration(openDialog([]))
    #expect(any.canChooseFiles && !any.canChooseDirectories && any.allowedContentTypes.isEmpty)
}

/// **F4** (`SV-AM` item 4). `.fileImporter(…[.folder])` presents a dialog
/// choosing directories only and completes with a **directory URL** for the
/// platform's path — even one that does not exist, so the URL is not read off
/// the file system; a file importer's URL for the same missing path is not a
/// directory URL.
///
/// Mutation **MF4**: `chosenURLs` ignores `directoriesOnly`.
@MainActor
@Test func aFolderImporterCompletesWithADirectoryURL() throws {
    let m = PSModel()
    m.shown = true
    var urls: [URL] = []
    let (window, platform) = try psWindow {
        Column {
            psLeaf().fileImporter(isPresented: m.binding, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { urls.append(url) }
            }
        }
    }
    window.drawFrameIfNeeded()
    let dialog = try #require(platform.presentedFileDialogs.first)
    #expect(dialog.kind == .open(allowsMultipleSelection: false))
    #expect(dialog.allowedTypes.map(\.identifier) == ["public.folder"])
    #expect(dialog.canChooseDirectories && !dialog.canChooseFiles)
    let missing = "/tmp/metalui-no-such-repo-\(UUID().uuidString)"
    psDeliver(platform, dialog.token, .chosen([missing]))
    try #require(urls.count == 1)
    #expect(urls[0].path == missing)
    #expect(urls[0].hasDirectoryPath, "a folder dialog answers with a directory")
    #expect(!URL(fileURLWithPath: missing).hasDirectoryPath, "the control: Foundation alone says file")
    #expect(!m.shown)
    withExtendedLifetime(window) {}
}

/// **F5** (`SV-AM` item 4). `FileDialogs.openFiles(allowedContentTypes:
/// [.folder])` returns directory URLs too. (F4's mutation site, named for the
/// async half: MF4 reddens both.)
@MainActor
@Test func openFilesOverAFolderTypeReturnsDirectoryURLs() async throws {
    let (window, platform) = try psWindow { Column { psLeaf() } }
    window.drawFrameIfNeeded()
    let dialogs = window.fileDialogs
    let (task, box) = fdStart { try await dialogs.openFiles(allowedContentTypes: [.folder]) }
    defer { task.cancel() }
    try #require(await fdYield { !platform.presentedFileDialogs.isEmpty })
    let dialog = platform.presentedFileDialogs[0]
    #expect(dialog.canChooseDirectories && !dialog.canChooseFiles)
    let missing = "/tmp/metalui-no-such-dir-\(UUID().uuidString)"
    psDeliver(platform, dialog.token, .chosen([missing]))
    try #require(await fdYield { box.result != nil })
    let urls = try #require(try box.result?.get())
    #expect(urls.map(\.path) == [missing])
    #expect(urls.allSatisfy { $0.hasDirectoryPath })
    withExtendedLifetime(window) {}
}
