import Foundation
import MetalUICore
import MetalUIPlatform

// The clipboard beyond text (rulings `CB-A`…`CB-N`; spec
// `docs/superpowers/specs/2026-10-14-clipboard-types-design.md`). `Clipboard`
// is the imperative API; `ClipboardAttachment` is what the three modifiers
// (`ClipboardModifiers.swift`) hang on an element.

extension ContentType {
    /// The built-in type named `identifier`, if it is one (`CB-F`: an offered
    /// type carries its parents so a `.data` destination reads a `.json` item).
    static func builtIn(_ identifier: String) -> ContentType? {
        [ContentType.item, .data, .text, .plainText, .utf8PlainText, .url, .fileURL, .json, .image, .png, .tiff, .jpeg]
            .first { $0.identifier == identifier }
    }
}

extension Transferable {
    /// This value as clipboard representations (ruling `CB-C`): one per exported
    /// type that exports, most preferred first, **zero-byte ones dropped**
    /// (`CB-I`).
    func clipboardRepresentations() -> [ClipboardRepresentation] {
        exportedContentTypes().compactMap { type in
            guard let data = exported(as: type), !data.isEmpty else { return nil }
            return ClipboardRepresentation(type: type.pasteboardType, bytes: [UInt8](data))
        }
    }
}

extension Transferable {
    /// This value as one outgoing item with every representation encoded now, zero-byte ones dropped;
    /// `nil` when none remains (`CB-I`, `CP-E`). The test harness's route to a multi-item clipboard.
    package func clipboardItem() -> ClipboardItem? { clipboardItem(lazily: false) }

    /// This value as one outgoing item (`CP-F`, `CP-N`). `lazily` captures **this value** and defers only the byte
    /// encoding: one `.later` representation per exported type, listed whether or not it will export bytes (`CB-I` cannot
    /// be applied before the exporter runs, divergence 716). Not lazy, every representation is encoded now and a
    /// zero-byte one dropped. `nil` when no representation remains.
    func clipboardItem(lazily: Bool) -> ClipboardItem? {
        guard lazily else {
            let payloads = clipboardRepresentations().map { ClipboardPayload(type: $0.type, bytes: .now($0.bytes)) }
            return payloads.isEmpty ? nil : ClipboardItem(payloads: payloads)
        }
        // The value crosses into a main-actor closure; it is a copy only that closure reads (`CP-F`).
        nonisolated(unsafe) let value = self
        let payloads = exportedContentTypes().map { type in
            ClipboardPayload(type: type.pasteboardType, bytes: .later {
                value.exported(as: type).map { [UInt8]($0) } ?? []
            })
        }
        return payloads.isEmpty ? nil : ClipboardItem(payloads: payloads)
    }
}

/// How a clipboard's items are imported as a `Transferable` (ruling `CB-F`):
/// walk the destination's `importedContentTypes()` in order; for each, the first
/// offered type that is it or conforms to it, read lazily, and handed to
/// `T(importing:contentType:)` told the **destination's** type. A type whose
/// bytes are absent or refused moves on to the next imported type.
@MainActor
func importClipboardItem<T: Transferable>(_ item: DropItem, as type: T.Type) -> T? {
    for imported in T.importedContentTypes() {
        guard let offered = item.types.first(where: { $0.satisfies(imported.identifier) }),
              let bytes = item.load(offered.identifier),
              let value = T(importing: Data(bytes), contentType: imported) else { continue }
        return value
    }
    return nil
}

/// The clipboard of one window (ruling `CB-J`): typed `Transferable` values
/// on the platform's system clipboard, with plain text as a fallback type the
/// value itself lists. MetalUI-only (class `M`): SwiftUI has no imperative
/// clipboard (apps use `NSPasteboard`). Reach it as ``Window/clipboard``.
///
/// Run from input. A `Clipboard` has no public initialiser. Read it from a view with
/// ``EnvironmentValues/clipboard`` (`CB-S`).
@MainActor
public struct Clipboard {
    /// Held strongly by ``Window/clipboard`` (a window's own handle), weakly by the environment's (`CB-S`).
    private nonisolated(unsafe) let strongPlatform: (any PlatformWindow)?   // only read on the main actor
    private let source: ClipboardSource?
    /// What `==` compares (`CB-S`): the window's platform for ``Window/clipboard``, the window's stamped source for
    /// the environment's, `nil` for the no-op one.
    private nonisolated let identity: ObjectIdentifier?

    init(platform: any PlatformWindow) {
        strongPlatform = platform
        source = nil
        identity = ObjectIdentifier(platform)
    }

    /// A clipboard that reaches its window through `source`, which holds it weakly, so one kept in a stored
    /// environment does not retain the window; `nil` is the no-op clipboard (`CB-S`).
    nonisolated init(weakly source: ClipboardSource?) {
        strongPlatform = nil
        self.source = source
        identity = source.map { ObjectIdentifier($0) }
    }

    /// The window's platform; `nil` for the no-op clipboard or once the window is gone.
    var platform: (any PlatformWindow)? { strongPlatform ?? source?.platformWindow }

    /// Replaces the clipboard with `item`: one representation per type it
    /// exports, most preferred first (list `.utf8PlainText` after your own type
    /// for a text fallback, `CB-C`). Zero-byte representations are dropped; when
    /// nothing remains this writes nothing, keeps the clipboard's contents and
    /// answers `false` (`CB-I`). Answers whether the platform accepted it.
    @discardableResult
    public func write<T: Transferable>(_ item: T) -> Bool {
        write([item])
    }

    /// Replaces the clipboard with `items`, one clipboard item each (`CP-C`), in order; an empty array
    /// writes nothing and answers `false`. Each is encoded **now** (the answer needs it: an item that
    /// exports zero bytes is dropped, `CB-I`, and with none left nothing is written); `copyable` and
    /// `cuttable` defer the encoding to the consumer's read where the platform can (`CP-F`, `CP-N`).
    @discardableResult
    public func write<T: Transferable>(_ items: [T]) -> Bool {
        let encoded = items.compactMap { $0.clipboardItem(lazily: false) }
        guard !encoded.isEmpty, let platform else { return false }
        return platform.writeClipboard(items: encoded)
    }

    /// The clipboard read as a `T` through `T.importedContentTypes()` in its
    /// order (`CB-F`), so a type importing `[custom, .utf8PlainText]` falls back
    /// to text; `nil` when nothing it imports is present or none initialises.
    public func read<T: Transferable>(_ type: T.Type = T.self) -> T? {
        importClipboardItem(item, as: type)
    }

    /// Every clipboard item `T` imports, in clipboard order (`CP-D`); an item it cannot import is
    /// skipped. `read` is the first item only. MetalUI-only (class `M`).
    public func readAll<T: Transferable>(_ type: T.Type = T.self) -> [T] {
        items.compactMap { importClipboardItem($0, as: type) }
    }

    /// How many items the clipboard holds (`CP-D`): `0` when empty, `1` for text or any
    /// single-item copy. MetalUI-only (class `M`).
    public var itemCount: Int { platform?.clipboardItems().count ?? 0 }

    /// The identifiers of the types the clipboard holds (item 0's), most preferred first
    /// as the platform lists them.
    public var contentTypes: [String] { platform?.clipboardTypeIdentifiers() ?? [] }

    /// Whether the clipboard holds `type` or a type that conforms to it.
    public func hasContent(of type: ContentType) -> Bool {
        contentTypes.contains { identifier in
            identifier == type.identifier
                || (ContentType.builtIn(identifier)?.conforms(to: type) ?? false)
        }
    }

    /// The bytes of item 0 stored as `type` or as a type that conforms to it, the first such
    /// type in the platform's order (`SOC-G`); `nil` when the clipboard holds none, or its
    /// bytes are empty. `readData(of: .image)` takes whichever image the source listed first
    /// (use ``read(_:)`` with ``ImageData`` to learn which); `readData(of: .png)` takes PNG
    /// only: nothing converts between formats. Mirrors ``hasContent(of:)``. MetalUI-only
    /// (class `M`).
    public func readData(of type: ContentType) -> Data? {
        let item = self.item
        for offered in item.types where offered.satisfies(type.identifier) {
            if let bytes = item.load(offered.identifier), !bytes.isEmpty { return Data(bytes) }
        }
        return nil
    }

    /// Every clipboard item as a lazily read `DropItem` (`CB-F`, `CP-D`), in clipboard order.
    var items: [DropItem] {
        guard let platform else { return [] }
        return platform.clipboardItems().enumerated().map { index, identifiers in
            DropItem(types: identifiers.map { ContentType.builtIn($0)?.pasteboardType ?? PasteboardType(identifier: $0) },
                     load: { [platform] identifier in platform.readClipboard(item: index, identifier: identifier) })
        }
    }

    /// The clipboard's item 0 as one `DropItem` (`CB-F`): the platform's identifiers,
    /// lazily read.
    var item: DropItem {
        guard let platform else { return DropItem(types: [], load: { _ in nil }) }
        let types = platform.clipboardTypeIdentifiers().map { identifier in
            ContentType.builtIn(identifier)?.pasteboardType ?? PasteboardType(identifier: identifier)
        }
        return DropItem(types: types, load: { [platform] identifier in
            platform.readClipboard(identifier: identifier)
        })
    }
}

/// Two clipboards are equal when they reach the same window (`CB-S`), so a component that reads
/// ``EnvironmentValues/clipboard`` stays replayable (`EE-A`: an environment reading must compare). All no-op
/// clipboards are equal.
extension Clipboard: Equatable {
    public nonisolated static func == (l: Clipboard, r: Clipboard) -> Bool { l.identity == r.identity }
}

extension Window {
    /// This window's clipboard (ruling `CB-J`), for code outside a view: the
    /// same calls `copyable`, `cuttable` and `pasteDestination` make. MetalUI-only.
    public var clipboard: Clipboard { Clipboard(platform: platformWindow) }
}

/// The window a ``Clipboard`` read from the environment writes to, held weakly (`CB-S`): the window stamps
/// one at its root, as it does a `URLOpener` (`LI-D`), and the stamp is an identity reading.
@MainActor
final class ClipboardSource {
    private(set) weak var platformWindow: (any PlatformWindow)?

    init(platformWindow: any PlatformWindow) { self.platformWindow = platformWindow }
}

struct ClipboardSourceKey: EnvironmentKey {
    static var defaultValue: ClipboardSource? { nil }
}

extension EnvironmentValues {
    /// The hosting window's clipboard, for an action that copies (a "Copy" button): `@Environment(\.clipboard)
    /// var clipboard`, then `clipboard.write("text")` in the action. **MetalUI-only (class `M`): SwiftUI has no
    /// environment clipboard** (apps use `UIPasteboard`/`NSPasteboard`); this is ``Window/clipboard`` reachable
    /// from inside the view tree (`CB-S`). Read-only: the window supplies it. The value holds the window
    /// weakly, so a stored environment keeps nothing alive, and **outside a window, or after it closed, it is a
    /// no-op clipboard** (`write` answers `false`, reads answer `nil`, `itemCount` is `0`). Write from input
    /// (an action, a key handler), never from a phase: a build or paint that writes the clipboard is a side
    /// effect on every frame, as for ``Window/clipboard``. Two windows' environments hold their own.
    public var clipboard: Clipboard { Clipboard(weakly: self[ClipboardSourceKey.self]) }

    /// The window's clipboard source, stamped at the root (`CB-S`): an identity reading, so it never makes a
    /// position uncomparable.
    mutating func stampClipboardSource(_ source: ClipboardSource) {
        setCustom(ClipboardSourceKey.self, source, reading: .object(ObjectIdentifier(source)))
    }
}

/// What `copyable`, `cuttable` and `pasteDestination` attach to an element:
/// one class box in `KeyboardAttachment` (ruling `CB-M`; `Handlers` keeps its
/// nineteen members). Each modifier makes a new box with its own closure
/// replaced and the others kept.
final class ClipboardAttachment {
    /// Evaluated at copy time; one outgoing item per value (`CP-C`).
    let copy: (() -> [ClipboardItem])?
    /// Runs the cut's action once and answers what it returned, as items.
    let cut: (@MainActor () -> [ClipboardItem])?
    /// Imports every clipboard item it can and runs the action; whether it ran (`CP-C`).
    let paste: (@MainActor ([DropItem]) -> Bool)?

    init(copy: (() -> [ClipboardItem])? = nil,
         cut: (@MainActor () -> [ClipboardItem])? = nil,
         paste: (@MainActor ([DropItem]) -> Bool)? = nil) {
        self.copy = copy
        self.cut = cut
        self.paste = paste
    }

    /// The commands this attachment enables in the Edit menu (`CB-G`).
    var commands: ClipboardCommands {
        var result: ClipboardCommands = []
        if copy != nil { result.insert(.copy) }
        if cut != nil { result.insert(.cut) }
        if paste != nil { result.insert(.paste) }
        return result
    }

    func replacingCopy(_ copy: @escaping () -> [ClipboardItem]) -> ClipboardAttachment {
        ClipboardAttachment(copy: copy, cut: cut, paste: paste)
    }
    func replacingCut(_ cut: @escaping @MainActor () -> [ClipboardItem]) -> ClipboardAttachment {
        ClipboardAttachment(copy: copy, cut: cut, paste: paste)
    }
    func replacingPaste(_ paste: @escaping @MainActor ([DropItem]) -> Bool) -> ClipboardAttachment {
        ClipboardAttachment(copy: copy, cut: cut, paste: paste)
    }

    static func copying<T: Transferable>(_ items: @escaping () -> [T],
                                         over existing: ClipboardAttachment?) -> ClipboardAttachment {
        let copy: () -> [ClipboardItem] = { items().compactMap { $0.clipboardItem(lazily: true) } }
        return (existing ?? ClipboardAttachment()).replacingCopy(copy)
    }

    static func cutting<T: Transferable>(_ action: @escaping @MainActor () -> [T],
                                         over existing: ClipboardAttachment?) -> ClipboardAttachment {
        let cut: @MainActor () -> [ClipboardItem] = { action().compactMap { $0.clipboardItem(lazily: true) } }
        return (existing ?? ClipboardAttachment()).replacingCut(cut)
    }

    static func pasting<T: Transferable>(_ type: T.Type,
                                         action: @escaping @MainActor ([T]) -> Void,
                                         validator: @escaping @MainActor ([T]) -> [T],
                                         over existing: ClipboardAttachment?) -> ClipboardAttachment {
        let paste: @MainActor ([DropItem]) -> Bool = { items in
            let values = items.compactMap { importClipboardItem($0, as: T.self) }
            guard !values.isEmpty else { return false }
            let accepted = validator(values)
            guard !accepted.isEmpty else { return false }
            action(accepted)
            return true
        }
        return (existing ?? ClipboardAttachment()).replacingPaste(paste)
    }
}
