import MetalUI

/// The variable-height list demo (ruling `VL-K`; spec
/// `2026-10-08-variable-height-list-design.md` §5 lane 3), reached with
/// `METALUI_LIST_DEMO=1 swift run MetalUIDemo` (and `MetalUISDLDemo`): 300
/// rows of wrapping text in three lengths, sized from their content
/// (`List(_:selection:estimatedRowHeight:rowContent:)`, rulings `VL-A`,
/// `VL-B`), selectable as a set, inside a `ScrollView` that fills the window,
/// and a "Jump to row 250" button that scrolls through `ScrollViewReader`.
///
/// **The human looks** (`docs/verification/human-checks.md` group VL, VL1–VL5):
/// no gap and no overlap while scrolling, the row on top staying put while
/// rows above it re-measure after a resize, the jump landing on row 250,
/// selection as in the controls demo's list, rows re-wrapping as the window's
/// width changes.
///
/// Nothing here is in the default demo, so the fourteen offscreen images and
/// `Expected.swift` do not move. **Its own function**, and its parts are their
/// own functions (the Windows 1 MB stack rule, `demoContent()`'s note); built
/// on a 1 MB thread by `everyProductionTreeBuildsOnAOneMegabyteThread`, and
/// settled headless by `theVariableListDemoSettlesHeadless`.
@MainActor
public func variableListDemoContent() -> some Element {
    Column(gap: Pixels(12)) {
        VariableListDemo()
    }
    .alignItems(.stretch)
    .padding(Pixels(24))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.surface)
}

/// One row of the demo: an id and its text, of one of three lengths.
struct VariableListDemoItem: Identifiable {
    var id: Int
    var text: String
}

/// The three texts the rows cycle through: one line, a couple of lines, a
/// paragraph — so the list has rows of three heights at any window width.
private let variableListDemoTexts = [
    "A short row.",
    "A medium row whose text runs long enough to wrap onto a second line in a window of ordinary width.",
    "A long row. Its text is a whole paragraph, so it wraps onto several lines and makes this row "
        + "several times the height of a short one; resizing the window re-wraps it and re-measures "
        + "the row at the list's new width, while the row on top of the viewport keeps its place.",
]

/// The demo's 300 rows (row `i` has text `i % 3`).
let variableListDemoItems: [VariableListDemoItem] = (0..<300).map { i in
    VariableListDemoItem(id: i, text: "Row \(i) — " + variableListDemoTexts[i % 3])
}

/// The demo's state and its two parts — the header and the scrolled list —
/// under one `ScrollViewReader` so the header's button reaches the list's
/// rows. Layout-transparent: both parts are the root `Column`'s children.
struct VariableListDemo: Component {
    /// The selected row ids (a set: ⌘- and ⇧-clicks, `DD-Z`).
    @State var picked: Set<Int> = []

    var content: some ElementGroup {
        ScrollViewReader { proxy in
            variableListDemoHeader(selected: picked.count) { proxy.scrollTo(250, anchor: .top) }
            variableListDemoList(selection: $picked)
        }
    }
}

/// The demo's title, its jump button and the selection count.
@MainActor
func variableListDemoHeader(selected: Int, jump: @escaping @MainActor () -> Void) -> some Element {
    Row(gap: Pixels(16)) {
        Text("Variable-height List").font(size: 22)
        Button("Jump to row 250", action: jump)
        Text("Selected: \(selected)")
    }
    .alignItems(.center)
}

/// The scrolled, content-sized, selectable list.
@MainActor
func variableListDemoList(selection: Binding<Set<Int>>) -> some Element {
    Box {
        List(variableListDemoItems, selection: selection) { item in
            Text(item.text)
                .padding(Pixels(6))
        }
    }
    // Greedy on both axes, answering below its content (`LR-ET`): the list
    // takes the window's remaining height and its whole width (VL5's re-wrap).
    .frame(minWidth: Pixels(0), maxWidth: .infinity, minHeight: Pixels(0), maxHeight: .infinity)
    .background(.surfaceSecondary)
}
