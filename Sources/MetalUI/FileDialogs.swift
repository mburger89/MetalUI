import Foundation
import MetalUICore
import MetalUIPlatform

// File dialogs: SwiftUI's `.fileImporter`/`.fileExporter` subset (ruling
// `SV-C`) and MetalUI's async call (`SV-D`, `SV-AD` item 2). SwiftUI's side is
// `docs/probes/swiftui-platform-services.swift`, arms `D1`–`D5` and `X1`–`X5`;
// the async call has no SwiftUI counterpart (gpui's `prompt_for_paths` is the
// comparison).

/// Why a file dialog could not answer (ruling `SV-D` item 2). A cancelled
/// dialog is not an error: `FileDialogs.openFiles` returns `[]` and
/// `saveFile` `nil`, and an importer calls nothing.
public enum FileDialogError: Error, Equatable {
    /// No window to show it on: an environment no window stamped (a bare
    /// `EnvironmentValues()`, a headless `renderFrame`), or the window is gone.
    case noWindow
    /// The platform cannot show a file dialog
    /// (`PlatformWindow.presentFileDialog` answered `false`).
    case unavailable
    /// A dialog or alert is already up in that window — one at a time, as
    /// AppKit's one sheet.
    case busy
    /// The platform reported a failure; its message (SDL's `SDL_GetError()`,
    /// e.g. no portal or zenity on a Linux desktop).
    case platform(String)
}

/// Why a `.fileExporter` could not write (ruling `SV-C` item 3).
public enum FileExportError: Error, Equatable {
    /// The exporter's `item` was `nil` when a destination was chosen (`X5`:
    /// the dialog still presents), or it exports no bytes at all.
    case noItem
}

/// The window's open and save dialogs as async calls — MetalUI-only (ruling
/// `SV-D`): read `@Environment(\.fileDialogs)` in a view and call it from a
/// `Task` in a button's action, or use `Window.fileDialogs` from a menu
/// command.
///
/// ```swift
/// @Environment(\.fileDialogs) var dialogs
/// // …
/// Button("Import…") {
///     Task {
///         for url in try await dialogs.openFiles(allowedContentTypes: [.json]) { load(url) }
///     }
/// }
/// ```
///
/// **Holds its window weakly**, so a captured value never keeps a closed
/// window alive (`.onClick { window.x() }`'s cycle); once the window is gone a
/// call throws `FileDialogError.noWindow`. One dialog or alert at a time per
/// window: a call while one is up throws `.busy`. Cancelling the awaiting task
/// dismisses the dialog and throws `CancellationError`. On Linux and Windows
/// the answer arrives on another thread and resumes the task through the main
/// queue, which `App.run()` drains (`SV-H`).
@MainActor
public struct FileDialogs {
    weak var window: Window?

    nonisolated init(window: Window?) {
        self.window = window
    }

    /// Shows an open dialog offering `allowedContentTypes` (empty: every file)
    /// and returns the chosen files' URLs — files only, several when
    /// `allowsMultipleSelection` — or `[]` when the user cancels.
    ///
    /// - Throws: `FileDialogError` (`.noWindow`, `.unavailable`, `.busy`,
    ///   `.platform`), or `CancellationError` when the awaiting task is
    ///   cancelled.
    public func openFiles(allowedContentTypes: [ContentType],
                          allowsMultipleSelection: Bool = false) async throws -> [URL] {
        guard let window else { throw FileDialogError.noWindow }
        switch try await window.runFileDialog(kind: .open(allowsMultipleSelection: allowsMultipleSelection),
                                              types: allowedContentTypes) {
        case .chosen(let paths): return paths.map { URL(fileURLWithPath: $0) }
        case .cancelled: return []
        case .failed(let message): throw FileDialogError.platform(message)
        }
    }

    /// Shows a save dialog offering `contentTypes` (empty: any name), its name
    /// field holding `defaultFilename`, and returns the chosen URL — MetalUI
    /// writes nothing — or `nil` when the user cancels.
    ///
    /// - Throws: as `openFiles(allowedContentTypes:allowsMultipleSelection:)`.
    public func saveFile(contentTypes: [ContentType] = [], defaultFilename: String? = nil) async throws -> URL? {
        guard let window else { throw FileDialogError.noWindow }
        switch try await window.runFileDialog(kind: .save(defaultFilename: defaultFilename), types: contentTypes) {
        case .chosen(let paths): return paths.first.map { URL(fileURLWithPath: $0) }
        case .cancelled: return nil
        case .failed(let message): throw FileDialogError.platform(message)
        }
    }
}

extension Window {
    /// This window's open and save dialogs as async calls (ruling `SV-D` item
    /// 1) — for a menu-bar command, which runs outside any view; a view reads
    /// `@Environment(\.fileDialogs)`. The value holds this window weakly.
    public var fileDialogs: FileDialogs { FileDialogs(window: self) }

    /// Presents `kind` over `types` and suspends until the platform answers
    /// (`SV-D`): one request in flight per window (`.busy` otherwise), the
    /// continuation resumed from input (`handleFileDialogResult`), a cancelled
    /// task dismissing the dialog.
    func runFileDialog(kind: PlatformFileDialog.Kind,
                       types: [ContentType]) async throws -> FileDialogResultEvent.Outcome {
        guard presentations.inFlight == nil else { throw FileDialogError.busy }
        let token = presentations.makeToken()
        let dialog = PlatformFileDialog(token: token, kind: kind, allowedTypes: types.map(\.platformFileType))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<FileDialogResultEvent.Outcome, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                guard presentations.inFlight == nil else {
                    continuation.resume(throwing: FileDialogError.busy)
                    return
                }
                presentations.inFlight = .call(token: token, continuation: continuation)
                if !presentFileDialogOnPlatform(dialog) {
                    presentations.inFlight = nil
                    continuation.resume(throwing: FileDialogError.unavailable)
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.cancelFileDialog(token: token) }
        }
    }

    /// A cancelled call (`SV-D` item 3): dismiss its dialog and throw
    /// `CancellationError` into the awaiting task.
    private func cancelFileDialog(token: Int) {
        guard case .call(let current, let continuation)? = presentations.inFlight, current == token else { return }
        presentations.inFlight = nil
        dismissPresentationOnPlatform(token: token)
        continuation.resume(throwing: CancellationError())
    }
}

// MARK: - The modifiers (`SV-C`)

extension ElementGroup {
    /// Presents an open dialog while `isPresented` is `true` — SwiftUI's
    /// `fileImporter(isPresented:allowedContentTypes:allowsMultipleSelection:onCompletion:)`
    /// (ruling `SV-C`; probe arms `D1`–`D5`), with MetalUI's `ContentType` in
    /// place of `UTType`.
    ///
    /// Files only, filtered by `allowedContentTypes` (empty: every file; on
    /// Linux and Windows by filename extension alone, divergence 129). Shown
    /// after the frame in which `isPresented` turned `true` — a sheet on the
    /// window on AppKit — and not again while it is up. When it ends,
    /// `isPresented` is written `false` first, then: a choice calls
    /// `onCompletion(.success(urls))`; a cancel calls **nothing** (`D2`); a
    /// platform failure, or a platform that cannot show one, calls
    /// `onCompletion(.failure(FileDialogError…))`. Setting `isPresented` to
    /// `false` while it is up dismisses it with no call (`D3`). Callbacks run
    /// from input on the main actor, dispatched to this group, so `@State`
    /// writes are legal.
    public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [ContentType],
                             allowsMultipleSelection: Bool,
                             onCompletion: @escaping (Result<[URL], Error>) -> Void) -> PresentationScope<Self> {
        PresentationScope(content: self, isPresented: isPresented, request: .fileDialog(
            kind: .open(allowsMultipleSelection: allowsMultipleSelection), types: allowedContentTypes,
            title: nil, prompt: nil, complete: { outcome in
                switch outcome {
                case .chosen(let paths): onCompletion(.success(paths.map { URL(fileURLWithPath: $0) }))
                case .cancelled: break
                case .failed(let error): onCompletion(.failure(error))
                }
            }))
    }

    /// The one-file `fileImporter`: as the multiple-selection form with
    /// `allowsMultipleSelection: false`, completing with the chosen file's URL
    /// (SwiftUI's `fileImporter(isPresented:allowedContentTypes:onCompletion:)`).
    public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [ContentType],
                             onCompletion: @escaping (Result<URL, Error>) -> Void) -> PresentationScope<Self> {
        fileImporter(isPresented: isPresented, allowedContentTypes: allowedContentTypes,
                     allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let first = urls.first { onCompletion(.success(first)) }
            case .failure(let error): onCompletion(.failure(error))
            }
        }
    }

    /// Presents a save dialog while `isPresented` is `true` and writes `item`
    /// to the chosen file — SwiftUI's
    /// `fileExporter(isPresented:item:contentTypes:defaultFilename:onCompletion:onCancellation:)`
    /// (ruling `SV-C`; probe arms `X1`–`X5`), with MetalUI's synchronous
    /// `Transferable` and `ContentType`.
    ///
    /// The dialog is titled and prompted "Export", its name field holding
    /// `defaultFilename`, filtered by `contentTypes` (`X1`). A `nil` `item`
    /// still presents (`X5`). When it ends, `isPresented` is written `false`
    /// first, then: a choice writes the bytes atomically and calls
    /// `onCompletion(.success(url))` — or `.failure` when the write throws or
    /// `item` is `nil` (`FileExportError.noItem`); a cancel calls
    /// `onCancellation()` (`X3`); a platform failure calls
    /// `onCompletion(.failure(FileDialogError…))`.
    ///
    /// **The bytes** (`SV-C` item 4): `item.exported(as:)` for the first of its
    /// exported types conforming to `contentTypes.first` (its own first type
    /// when `contentTypes` is empty); when none conforms, its first
    /// representation's bytes — so a `Data` of JSON exported as `.json` writes
    /// the data. The type names the file; the item supplies the bytes.
    public func fileExporter<T: Transferable>(isPresented: Binding<Bool>, item: T?,
                                              contentTypes: [ContentType] = [],
                                              defaultFilename: String? = nil,
                                              onCompletion: @escaping (Result<URL, Error>) -> Void,
                                              onCancellation: @escaping () -> Void = {}) -> PresentationScope<Self> {
        PresentationScope(content: self, isPresented: isPresented, request: .fileDialog(
            kind: .save(defaultFilename: defaultFilename), types: contentTypes,
            title: "Export", prompt: "Export", complete: { outcome in
                switch outcome {
                case .chosen(let paths):
                    guard let path = paths.first else { return }
                    let url = URL(fileURLWithPath: path)
                    guard let item, let bytes = exportedBytes(of: item, as: contentTypes.first) else {
                        onCompletion(.failure(FileExportError.noItem))
                        return
                    }
                    do {
                        try bytes.write(to: url, options: .atomic)
                        onCompletion(.success(url))
                    } catch {
                        onCompletion(.failure(error))
                    }
                case .cancelled: onCancellation()
                case .failed(let error): onCompletion(.failure(error))
                }
            }))
    }
}

/// The exporter's byte rule (`SV-C` item 4): the representation conforming to
/// `type` (or the item's first type), else the first representation.
func exportedBytes<T: Transferable>(of item: T, as type: ContentType?) -> Data? {
    let types = item.exportedContentTypes()
    if let target = type ?? types.first, let match = types.first(where: { $0.conforms(to: target) }),
       let bytes = item.exported(as: match) {
        return bytes
    }
    return types.first.flatMap { item.exported(as: $0) }
}
