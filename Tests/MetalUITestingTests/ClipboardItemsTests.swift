import Foundation
import MetalUI
import MetalUIPlatform
import MetalUITesting
import Testing

// Multi-item copy and paste, and lazy export (rulings `CP-C`, `CP-D`, `CP-F`, `CP-N`; spec
// `docs/superpowers/specs/2026-10-22-clipboard-extras-design.md` §5, tests 2.1-2.7). PLAIN imports; the clipboard is the headless
// window's private one. `Graph`/`Blob` are `ClipboardTypesTests`' types.

#if os(macOS)
private let primary: EventModifiers = .command
#else
private let primary: EventModifiers = .control
#endif

@MainActor private final class ItemsModel {
    var pasted: [[Graph]] = []
    var blobs: [[Blob]] = []
    var cuts = 0
    var log: [String] = []
}

@MainActor private func square(_ id: String) -> some StyledElement {
    Box().frame(width: Pixels(40), height: Pixels(40)).accessibilityIdentifier(id)
}

/// A value whose exporter counts its calls (the lazy export's instrument).
final class ExportCounter { var calls = 0 }

struct Counted: Transferable {
    static let contentType = ContentType("com.example.metalui.counted", conformingTo: [.data])
    let counter: ExportCounter
    var label: String
    func exportedContentTypes() -> [ContentType] { [Counted.contentType, .utf8PlainText] }
    static func importedContentTypes() -> [ContentType] { [Counted.contentType] }
    func exported(as contentType: ContentType) -> Data? {
        counter.calls += 1
        return Data("counted:\(label)".utf8)
    }
    init(counter: ExportCounter, label: String) { self.counter = counter; self.label = label }
    init?(importing data: Data, contentType: ContentType) { return nil }
}

/// 2.1 — `copyable([a, b])` writes two clipboard items and a `pasteDestination` receives `[a, b]` in order.
/// **Red before:** one item is written (the old `CB-C`) and the destination receives `[a]`.
/// **Mutation:** write the first item only (`ClipboardAttachment.copying` back to `.first`).
@Test @MainActor func aCopyOfTwoItemsWritesTwoAndAPasteReceivesBothInOrder() throws {
    let m = ItemsModel()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            square("src").focusable().copyable([Graph(label: "a"), Graph(label: "b")])
            square("dst").focusable().pasteDestination(for: Graph.self) { m.pasted.append($0) }
        }
    }
    window.typeKey(.tab)
    window.typeKey("c", modifierFlags: primary)
    #expect(window.clipboardItems.count == 2, "two items on the clipboard: \(window.clipboardItems)")
    window.typeKey(.tab)
    window.typeKey("v", modifierFlags: primary)
    #expect(m.pasted == [[Graph(label: "a"), Graph(label: "b")]], "one action call with both, in order")
}

/// 2.2 — items the destination cannot import are skipped, and a clipboard with none importable declines so the next
/// stage runs (`CB-P`). **Mutation:** claim the key with an empty array (no `guard !values.isEmpty`).
@Test @MainActor func aPasteSkipsWhatItCannotImportAndDeclinesWithNothingImportable() throws {
    let m = ItemsModel()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            square("dst").focusable().pasteDestination(for: Blob.self) { m.blobs.append($0) }
            Button("Paste command") { m.log.append("button") }.keyboardShortcut("v")
        }
    }
    window.typeKey(.tab)
    window.setClipboard(items: [Graph(label: "x"), Graph(label: "y")])
    window.typeKey("v", modifierFlags: primary)
    #expect(m.blobs.isEmpty)
    #expect(m.log == ["button"], "nothing importable: declined, the Button's shortcut ran")
    // Separating arm: a Blob between two Graphs is the one value.
    func graphItem(_ label: String) -> ClipboardItem {
        ClipboardItem(payloads: [ClipboardPayload(type: PasteboardType(identifier: Graph.contentType.identifier), bytes: .now(Array("graph:\(label)".utf8)))])
    }
    let blob = ClipboardItem(payloads: [ClipboardPayload(type: PasteboardType(identifier: Blob.contentType.identifier), bytes: .now([7]))])
    window.setClipboard(items: [graphItem("x"), blob, graphItem("y")])
    window.typeKey("v", modifierFlags: primary)
    #expect(m.blobs == [[Blob(bytes: [7])]])
    #expect(m.log == ["button"])
}

/// 2.3 — the validator runs over the whole array and the action sees the filtered array.
/// **Mutation:** validate only the first value.
@Test @MainActor func theValidatorFiltersTheWholeArrayAndTheActionSeesTheFilteredOne() throws {
    let m = ItemsModel()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            square("dst").focusable().pasteDestination(for: Graph.self, action: { m.pasted.append($0) },
                                                      validator: { $0.filter { $0.label.hasPrefix("ok") } })
        }
    }
    window.typeKey(.tab)
    window.setClipboard(items: [Graph(label: "no"), Graph(label: "ok1"), Graph(label: "ok2")])
    window.typeKey("v", modifierFlags: primary)
    #expect(m.pasted == [[Graph(label: "ok1"), Graph(label: "ok2")]])
}

/// 2.4 — a cut returning several runs its action once and writes all of them.
/// **Mutation:** run the action twice (as `CB-`'s M3).
@Test @MainActor func aCutOfSeveralItemsRunsOnceAndWritesAll() throws {
    let m = ItemsModel()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            square("src").focusable().cuttable(for: Graph.self) {
                m.cuts += 1
                return [Graph(label: "a"), Graph(label: "b"), Graph(label: "c")]
            }
        }
    }
    window.typeKey(.tab)
    window.typeKey("x", modifierFlags: primary)
    #expect(m.cuts == 1)
    #expect(window.clipboardItems.count == 3)
}

/// 2.5 — `Clipboard.write([…])` writes every item, `readAll` and `itemCount` count them, an empty array writes nothing
/// and answers `false`. **Mutation:** `itemCount` from item 0 (reads 1).
@Test @MainActor func theWindowClipboardWritesReadsAndCountsEveryItem() throws {
    let window = try harnessWindow { Text("x") }
    let clipboard = window.window.clipboard
    #expect(clipboard.itemCount == 0 && clipboard.readAll(Graph.self).isEmpty)
    #expect(clipboard.write([Graph(label: "a"), Graph(label: "b"), Graph(label: "c")]))
    #expect(clipboard.itemCount == 3)
    #expect(clipboard.readAll(Graph.self) == [Graph(label: "a"), Graph(label: "b"), Graph(label: "c")])
    #expect(clipboard.read(Graph.self) == Graph(label: "a"), "`read` stays the first item")
    let none: [Graph] = []
    #expect(!clipboard.write(none), "an empty array writes nothing")
    #expect(clipboard.itemCount == 3, "and keeps the clipboard")
    window.setClipboard(text: "plain")
    #expect(clipboard.itemCount == 1)
    #expect(clipboard.readAll(Blob.self).isEmpty, "a type nothing offers reads none")
}

/// 2.6 — lazy export: with the default option the exporter runs zero times at copy and once at the first read; with
/// `clipboardExportsLazily = false` once at copy. **Mutation:** realise every `.later` at copy (the lazy arm reddens).
@Test @MainActor func aCopyExportsWhenAConsumerReadsAndEagerlyWhenTheOptionSaysSo() throws {
    for lazily in [true, false] {
        let counter = ExportCounter()
        let window = try harnessWindow(options: .init(clipboardExportsLazily: lazily)) {
            VStack(spacing: 0) {
                square("src").focusable().copyable([Counted(counter: counter, label: "z")])
            }
        }
        window.typeKey(.tab)
        window.typeKey("c", modifierFlags: primary)
        #expect(window.clipboardItems == [["com.example.metalui.counted", "public.utf8-plain-text"]], "listed without exporting")
        if lazily {
            #expect(counter.calls == 0 && window.clipboardExportCount == 0, "lazy: nothing exported at copy")
            let bytes = window.platformWindow.readClipboard(item: 0, identifier: "com.example.metalui.counted")
            #expect(bytes == Array("counted:z".utf8))
            #expect(counter.calls == 1 && window.clipboardExportCount == 1, "exported by the read")
        } else {
            #expect(counter.calls == 2 && window.clipboardExportCount == 2, "eager: both representations at copy")
        }
    }
}

/// 2.7 — a lazy representation that exports zero bytes is listed at the platform's listing and reads `nil` (divergence 716;
/// `CB-I` cannot be applied before the closure runs). **Mutation:** drop it at listing.
@Test @MainActor func anEmptyLazyRepresentationIsListedAndReadsNil() throws {
    let window = try harnessWindow { Text("x") }
    let type = PasteboardType(identifier: "com.example.empty")
    let text = PasteboardType(identifier: "public.utf8-plain-text")
    #expect(window.setClipboard(items: [ClipboardItem(payloads: [
        ClipboardPayload(type: type, bytes: .later { [] }),
        ClipboardPayload(type: text, bytes: .now(Array("t".utf8)))])]))
    #expect(window.clipboardItems == [["com.example.empty", "public.utf8-plain-text"]])
    #expect(window.platformWindow.readClipboard(item: 0, identifier: "com.example.empty") == nil)
    #expect(window.platformWindow.readClipboard(item: 0, identifier: "public.utf8-plain-text") == Array("t".utf8))
}
