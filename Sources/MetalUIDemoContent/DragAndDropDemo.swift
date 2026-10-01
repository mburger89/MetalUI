import MetalUI
import Foundation

/// The drag-and-drop demo (ruling `DN-Q`; spec
/// `2026-10-01-drag-and-drop-design.md` §7), reached with
/// `METALUI_DND_DEMO=1 swift run MetalUIDemo` (and the same variable for
/// `Backends/SDL`'s `MetalUISDLDemo`). Left: four chips — **Apple** (a
/// `String`), **example.com** (a web `URL`), **Custom preview** (a `String`
/// with a 60 × 60 accent square for its preview) and **Hold, then drag** (a
/// `String` with a long press, for human check N8) — and a selectable `List`
/// whose rows drag `"Row n"`. Right: four wells, each showing its last drop and
/// filling with `.accent` while `isTargeted`: **Text** (`String`), **Links and
/// files** (`URL`), **Anything** (`Data`, its byte count) and **Disabled**
/// (`String`, `.disabled(true)` — divergence 100).
///
/// **The human looks** (`docs/verification/human-checks.md` N1–N8): the
/// preview, the highlight, Escape, a row's click against its drag, Finder and
/// TextEdit drops, a chip dragged out of the window (AppKit; on SDL it stops at
/// the edge, divergence 101).
///
/// Nothing here is in the default demo, so the fourteen offscreen images and
/// `Expected.swift` do not move (`DN-Q`). Each section is its own function,
/// passed as an argument to a generic composing function — the Windows stack
/// rule `demoContent()`'s note records; built on a 1 MB thread by
/// `everyProductionTreeBuildsOnAOneMegabyteThread`.
@MainActor
public func dragAndDropDemoContent() -> some Element {
    dndRoot(header: dndHeader(), sources: dndSources(chips: dndChips(), rows: dndRows()), wells: dndWells())
}

/// The root: the header over the two columns.
@MainActor
private func dndRoot(header: some Element, sources: some Element, wells: some Element) -> some Element {
    Column(gap: Pixels(16)) {
        header
        Row(gap: Pixels(40)) {
            sources
            wells
        }
        .alignItems(.flexStart)
    }
    .alignItems(.flexStart)
    .padding(Pixels(24))
    .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .topLeading)
    .background(.surface)
}

@MainActor
private func dndHeader() -> some Element {
    Column(gap: Pixels(4)) {
        Text("Drag and Drop").font(size: 22)
        Text("Drag a chip or a row onto a well. Escape cancels. Drop files or text from another app.")
    }
    .alignItems(.flexStart)
}

/// The left column: the chips over the list.
@MainActor
private func dndSources(chips: some Element, rows: some Element) -> some Element {
    Column(gap: Pixels(16)) {
        chips
        rows
    }
    .alignItems(.flexStart)
}

/// A chip's look: its label padded on a rounded secondary surface.
@MainActor
private func chip(_ label: String) -> ModifiedElement<Text> {
    Text(label).padding(Pixels(10)).background(.surfaceSecondary).cornerRadius(Pixels(8))
}

@MainActor
private func dndChips() -> some Element {
    Row(gap: Pixels(12)) {
        chip("Apple").draggable("Apple")
        chip("example.com").draggable(URL(string: "https://example.com")!)
        chip("Custom preview").draggable("Custom") {
            Box().frame(width: Pixels(60), height: Pixels(60)).background(.accent).cornerRadius(Pixels(8))
        }
        // Human check N8 (`DN-U` item 1, `DN-Z` item 2): held past its long
        // press before moving, this chip does not drag.
        chip("Hold, then drag").draggable("Held").onLongPressGesture(perform: {})
    }
}

@MainActor
private func dndRows() -> some Element {
    Column { DragAndDropRows() }
}

@MainActor
private func dndWells() -> some Element {
    Column(gap: Pixels(12)) {
        DropWell(title: "Text", disabled: false) { (items: [String]) in items.joined(separator: ", ") }
        DropWell(title: "Links and files", disabled: false) { (items: [URL]) in
            items.map(\.absoluteString).joined(separator: ", ")
        }
        DropWell(title: "Anything", disabled: false) { (items: [Data]) in
            items.map { "\($0.count) bytes" }.joined(separator: ", ")
        }
        DropWell(title: "Disabled", disabled: true) { (items: [String]) in items.joined(separator: ", ") }
    }
    .alignItems(.flexStart)
}

/// One row of the demo's list.
struct DragAndDropRow: Identifiable {
    var id: Int
}

/// A selectable list whose rows drag `"Row n"`: a click selects, a drag does
/// not (`P4a`, `P4b`; human check N6).
struct DragAndDropRows: Component {
    @State var selected: Set<Int> = []

    var content: some ElementGroup {
        ScrollView {
            List((0..<20).map { DragAndDropRow(id: $0) }, selection: $selected, rowHeight: Pixels(24)) { row in
                Text("Row \(row.id)").draggable("Row \(row.id)")
            }
        }
        .frame(width: Pixels(260), height: Pixels(200))
        .background(.surfaceSecondary)
    }
}

/// A drop destination for `T` showing its last drop ("—" before one), filled
/// with `.accent` while targeted.
struct DropWell<T: Transferable>: Component {
    let title: String
    let disabled: Bool
    let describe: @MainActor ([T]) -> String
    @State var last = "—"
    @State var targeted = false

    init(title: String, disabled: Bool, describe: @escaping @MainActor ([T]) -> String) {
        self.title = title
        self.disabled = disabled
        self.describe = describe
    }

    var content: some ElementGroup {
        Column(gap: Pixels(6)) {
            Text(title).font(size: 15)
            Text(last)
        }
        .alignItems(.flexStart)
        .padding(Pixels(12))
        .frame(width: Pixels(320), height: Pixels(80), alignment: .topLeading)
        .background(targeted ? .accent : .surfaceSecondary)
        .cornerRadius(Pixels(10))
        .dropDestination(for: T.self, action: { items, _ in
            last = describe(items)
            return true
        }, isTargeted: { targeted = $0 })
        .disabled(disabled)
    }
}
