import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// The fixture of record 416 and 422 (`RK-AM`): Alloy's transcript. `ScrollView(.defaultScrollAnchor(.bottom)) > LazyVStack > ForEach` of `.equatable()`
// rows, each a tinted rounded chrome (`BlockChrome`'s `.background(tint).cornerRadius(8)`) around nested `.equatable()` paragraphs and a button, the last
// row streaming one word a frame, in a 420 x 600 window at scale 2. The bottom anchor moves the rows by a few points every frame; a row cut by the
// viewport edge cannot translate its paint record (`maskCrossingChanged`, `inexactTranslation`), a grafted row cannot prepaint, and the frame is redone.

/// A paragraph: the nested occurrence under a row. `==` on its text.
struct CTParagraph: Component, @MainActor Equatable {
    let text: String
    var content: some ElementGroup { Text(text).frame(maxWidth: .infinity, alignment: .leading) }
}

/// A row: tinted rounded chrome around two paragraphs and, on some rows, a button.
struct CTRow: Component, @MainActor Equatable {
    let id: Int
    let text: String
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 6) {
            CTParagraph(text: text).equatable()
            CTParagraph(text: "second paragraph \(id)").equatable()
            if id.isMultiple(of: 3) { Button("Allow") {} }
        }
        .padding(Edges(all: Pixels(8)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accent.opacity(0.18 + 0.04 * Double(id % 3)))
        .cornerRadius(Pixels(8))   // `BlockChrome`: a clip with a rounded mask, which a moved record cannot re-derive at the viewport edge
    }
}

func ctText(_ step: Int) -> String { "streaming" + (0..<step).map { " word\($0)" }.joined() }

struct CTRoot: Component {
    let side: RPSide
    var content: some ElementGroup {
        let rows = (0..<50).map { CTRow(id: $0, text: "row \($0) some words that wrap onto more than one line in a narrow column") }
            + [CTRow(id: 999, text: ctText(Int(side.inputs.offset)))]
        ScrollViewReader { _ in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Pixels(10)) {
                    ForEach(rows, id: \.id) { row in row.equatable() }
                }.padding(g49Inset)
            }
            .defaultScrollAnchor(.bottom).contentMargins(.bottom, Pixels(40), for: .scrollContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@MainActor func ctPair(warm: Int = 8, accessibility: Bool = false) throws -> RPPair<some Element> {
    try RPPair(size: sz(420, 600), scale: 2, warm: warm, accessibility: accessibility) { side in VStack(spacing: 0) { CTRoot(side: side) } }
}

/// The chrome transcript under an outer capturing scope (record 437, `FS-Z`): the root faded as one group, so each row's crossing mask scope opens with another
/// scope around it and is an inner scope. The rows whose clip crosses the viewport's straight edge still refuse their move by name (`maskCrossingChanged`,
/// `innerScope`) and the frame is redone, as `ctPair` did before a record seen through a crossing scope could move: the fixture the redo tests read.
@MainActor func ctOuterScopePair(warm: Int = 8, accessibility: Bool = false) throws -> RPPair<some Element> {
    try RPPair(size: sz(420, 600), scale: 2, warm: warm, accessibility: accessibility) { side in
        VStack(spacing: 0) { CTRoot(side: side) }.compositingGroup().opacity(0.99)
    }
}

/// One streamed word on both sides, settled, one frame each; the retaining window's frames of the step (a step may draw more than one).
@MainActor func ctStep(_ pair: RPPair<some Element>) async -> [FrameWork] {
    pair.onSide.inputs.offset += 1; pair.offSide.inputs.offset += 1
    pair.on.resetFrameWork()
    await rsSettle()
    pair.redraw()
    return pair.on.frameWork
}

// MARK: The shaped fixture (record 431, promoted at record 437)

/// A row whose button has a content shape: its hitbox refuses every layout move by name.
struct RAShapedRow: Component, @MainActor Equatable {
    let id: Int
    let text: String
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 6) {
            CTParagraph(text: text).equatable()
            Button("Allow") {}.contentShape(RoundedRectangle(cornerRadius: Pixels(4)))
        }
        .padding(Edges(all: Pixels(8)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accent.opacity(0.18))
        .cornerRadius(Pixels(8))
    }
}

struct RAShapedRoot: Component {
    let side: RPSide
    var content: some ElementGroup {
        let rows = (0..<50).map { RAShapedRow(id: $0, text: "row \($0) some words that wrap onto more than one line in a narrow column") }
            + [RAShapedRow(id: 999, text: ctText(Int(side.inputs.offset)))]
        ScrollViewReader { _ in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Pixels(10)) {
                    ForEach(rows, id: \.id) { row in row.equatable() }
                }.padding(g49Inset)
            }
            .defaultScrollAnchor(.bottom).contentMargins(.bottom, Pixels(40), for: .scrollContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@MainActor func ctShapedPair() throws -> RPPair<some Element> {
    try RPPair(size: sz(420, 600), scale: 2, warm: 8, accessibility: false) { side in VStack(spacing: 0) { RAShapedRoot(side: side) } }
}
