import MetalUI
import Observation
import Foundation

/// The clipboard demo (spec `2026-10-14-clipboard-types-design.md` §6, rulings
/// `CB-A`…`CB-N`), reached with `METALUI_CLIPBOARD_DEMO=1 swift run MetalUIDemo`
/// (and `MetalUISDLDemo`): the shape MetalCreator's graph editor needs.
///
/// - **Source**: a focusable box holding a `DemoGraph` (its own `ContentType`, with a
///   plain-text fallback), `copyable` and `cuttable`. Tab to it and press ⌘C / Ctrl-C
///   (or Edit ▸ Copy); ⌘X / Ctrl-X cuts (the node count drops by one).
/// - **Destination**: a focusable `pasteDestination` showing what arrived and as which
///   type (`graph` for the custom type, `text` for the fallback).
/// - **Text field**: pastes the fallback text; copying from it replaces the graph.
///
/// - **Several items and a paste button** (`CP-C`, `CP-B`): a second source copies **two** graphs, a destination
///   lists everything it received, and a `PasteButton` beside it is dimmed until a `DemoGraph` is on the clipboard.
///
/// Nothing here is in the default demo, so the fourteen offscreen images and `Expected.swift`
/// do not move. Each part is its own function passed to a generic composer (the Windows 1 MB
/// stack rule); built on a 1 MB thread by `everyProductionTreeBuildsOnAOneMegabyteThread`.
@MainActor
public func clipboardDemoContent() -> some Element {
    clipboardDemoRoot(header: clipboardDemoHeader(), source: clipboardDemoSource(),
                      destination: clipboardDemoDestination(), field: clipboardDemoField(),
                      multi: clipboardDemoMulti())
}

/// An app's own clipboard type with a plain-text fallback: its own type first, `.utf8PlainText`
/// after it (`CB-C`).
public struct DemoGraph: Transferable, Equatable {
    /// The demo's own content type.
    public static let contentType = ContentType("com.metalui.demo.graph", conformingTo: [.data])
    /// How many nodes the graph has.
    public var nodes: Int

    /// A graph of `nodes` nodes.
    public init(nodes: Int) { self.nodes = nodes }

    /// The custom type, then the text fallback.
    public func exportedContentTypes() -> [ContentType] { [DemoGraph.contentType, .utf8PlainText] }
    /// The custom type, then text (a pasted number of nodes).
    public static func importedContentTypes() -> [ContentType] { [DemoGraph.contentType, .utf8PlainText] }
    /// `nodes:N` for the custom type, `graph with N nodes` for text.
    public func exported(as contentType: ContentType) -> Data? {
        if contentType == DemoGraph.contentType { return Data("nodes:\(nodes)".utf8) }
        if contentType == .utf8PlainText { return Data("graph with \(nodes) nodes".utf8) }
        return nil
    }
    /// Reads either representation; text imports as its character count.
    public init?(importing data: Data, contentType: ContentType) {
        let text = String(decoding: data, as: UTF8.self)
        if contentType == DemoGraph.contentType {
            guard text.hasPrefix("nodes:"), let n = Int(text.dropFirst(6)) else { return nil }
            nodes = n
        } else if contentType == .utf8PlainText {
            nodes = text.count
        } else {
            return nil
        }
    }
}

/// The demo's state, written only from input (key handlers).
@MainActor
@Observable
public final class ClipboardDemoModel {
    /// The source's node count.
    public var nodes = 3
    /// What the destination last received.
    public var received = "nothing pasted yet"
    /// The text field's contents.
    public var field = ""
    /// The two graphs the pair source copies.
    public var pair = [1, 2]
    /// What the pair destination last received.
    public var receivedAll = "nothing pasted yet"
    /// What the paste button last delivered.
    public var buttonReceived = "nothing pasted yet"

    /// A fresh model.
    public init() {}

    /// Back to the launch state.
    public func reset() {
        nodes = 3; received = "nothing pasted yet"; field = ""
        pair = [1, 2]; receivedAll = "nothing pasted yet"; buttonReceived = "nothing pasted yet"
    }
}

/// The one model the demo and its tests share.
@MainActor public let clipboardDemoModel = ClipboardDemoModel()

@MainActor
private func clipboardDemoHeader() -> some Element {
    Text("Clipboard — Tab to the source, ⌘C / Ctrl-C (⌘X cuts), Tab to the destination, ⌘V / Ctrl-V")
        .font(size: 13)
}

@MainActor
private func clipboardDemoSource() -> some Element {
    let model = clipboardDemoModel
    return Box { Text("source: graph with \(model.nodes) nodes").font(size: 12) }
        .padding(Pixels(12))
        .frame(width: Pixels(260), height: Pixels(60))
        .background(.surface)
        .accessibilityIdentifier("clipboard-source")
        .focusable()
        .copyable([DemoGraph(nodes: model.nodes)])
        .cuttable(for: DemoGraph.self) {
            let cut = DemoGraph(nodes: model.nodes)
            model.nodes = max(0, model.nodes - 1)
            return [cut]
        }
}

@MainActor
private func clipboardDemoDestination() -> some Element {
    let model = clipboardDemoModel
    return Box { Text("destination: \(model.received)").font(size: 12) }
        .padding(Pixels(12))
        .frame(width: Pixels(260), height: Pixels(60))
        .background(.surface)
        .accessibilityIdentifier("clipboard-destination")
        .focusable()
        .pasteDestination(for: DemoGraph.self) { graphs in
            model.received = "\(graphs[0].nodes) nodes"
        }
}

@MainActor
private func clipboardDemoField() -> some Element {
    let model = clipboardDemoModel
    return TextField("Paste text here", text: model.field) { model.field = $0 }
        .frame(width: Pixels(260), height: Pixels(24))
        .accessibilityIdentifier("clipboard-field")
}

/// The several-items section, in its own function (the Windows 1 MB stack rule): a source copying two
/// graphs, a destination listing what it received and a paste button.
@MainActor
private func clipboardDemoMulti() -> some Element {
    clipboardDemoMultiRoot(source: clipboardDemoPairSource(), destination: clipboardDemoPairDestination(),
                           button: clipboardDemoPasteButton())
}

@MainActor
private func clipboardDemoPairSource() -> some Element {
    let model = clipboardDemoModel
    return Box { Text("pair source: graphs of \(model.pair[0]) and \(model.pair[1]) nodes").font(size: 12) }
        .padding(Pixels(12))
        .frame(width: Pixels(260), height: Pixels(60))
        .background(.surface)
        .accessibilityIdentifier("clipboard-pair-source")
        .focusable()
        .copyable([DemoGraph(nodes: model.pair[0]), DemoGraph(nodes: model.pair[1])])
}

@MainActor
private func clipboardDemoPairDestination() -> some Element {
    let model = clipboardDemoModel
    return Box { Text("pair destination: \(model.receivedAll)").font(size: 12) }
        .padding(Pixels(12))
        .frame(width: Pixels(260), height: Pixels(60))
        .background(.surface)
        .accessibilityIdentifier("clipboard-pair-destination")
        .focusable()
        .pasteDestination(for: DemoGraph.self) { graphs in
            model.receivedAll = graphs.map { "\($0.nodes)" }.joined(separator: ", ") + " nodes (\(graphs.count) items)"
        }
}

@MainActor
private func clipboardDemoPasteButton() -> some Element {
    let model = clipboardDemoModel
    return Row(gap: Pixels(12)) {
        PasteButton(payloadType: DemoGraph.self) { graphs in
            model.buttonReceived = "\(graphs.count) graphs, \(graphs.reduce(0) { $0 + $1.nodes }) nodes"
        }
        Text("button: \(model.buttonReceived)").font(size: 12)
    }
}

@MainActor
private func clipboardDemoMultiRoot(source: some Element, destination: some Element, button: some Element) -> some Element {
    Column(gap: Pixels(16)) {
        source
        destination
        button
    }
    .alignItems(.flexStart)
}

@MainActor
private func clipboardDemoRoot(header: some Element, source: some Element, destination: some Element,
                               field: some Element, multi: some Element) -> some Element {
    Column(gap: Pixels(16)) {
        header
        source
        destination
        field
        multi
    }
    .alignItems(.flexStart)
    .padding(Pixels(24))
    .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .topLeading)
    .background(.surface)
}
