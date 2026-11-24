import Foundation
import MetalUI

/// The text-selection demo (`TXS-A`..`TXS-H`, record 399, human checks group TXS), reached with
/// `METALUI_TEXT_SELECTION_DEMO=1 swift run MetalUIDemo`: Alloy's plugin log in miniature — a long stderr tail as one `Text`
/// with `.textSelection(.enabled)` in a scroller — beside the cases the human checks name: a field to focus (the press blurs it),
/// a selectable `Text` with a tap of its own and a plain `Text` for contrast.
///
/// Drag selects, ⌘C copies, ⌘A takes the log whole, a right click offers Copy and Select All. The tap counter shows whether a
/// press on the tapped `Text` selected it or fired the tap (`HC-TXS-4`). Nothing here is in the default demo, so the offscreen
/// images do not move. Each part is its own function (the Windows 1 MB stack rule).
@MainActor
public func textSelectionDemoContent() -> some Element {
    textSelectionRoot(header: textSelectionHeader(), controls: TextSelectionControls(), log: textSelectionLog())
}

/// A stderr tail of `lines` lines (about 55 bytes each; 1 200 of them is about 64 KiB, the largest Alloy shows).
func textSelectionLogText(lines: Int) -> String {
    (0..<lines).map { index in
        let level = ["INFO", "WARN", "ERROR", "DEBUG"][index % 4]
        return "2026-11-23T12:\(String(format: "%02d", index / 60 % 60)):\(String(format: "%02d", index % 60)) \(level) plugin[pg-sift] request \(index) finished in \(index * 7 % 900) ms"
    }.joined(separator: "\n")
}

@MainActor
private func textSelectionHeader() -> some Element {
    VStack(alignment: .leading, spacing: Pixels(4)) {
        Text("Plugin stderr").font(size: 16).bold()
        Text("Drag to select, double click a word, triple click a line, \u{2318}C to copy, \u{2318}A for the whole log, right click for the menu.")
            .font(size: 12)
    }
}

/// A field, a selectable `Text` with a tap and a plain `Text`, in one row's worth of state.
struct TextSelectionControls: Component {
    @State var note = "click here, then press the log"
    @State var taps = 0

    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(6)) {
            TextField("a field", text: $note).frame(width: 260)
            Text("A selectable Text with its own tap (taps: \(taps))")
                .textSelection(.enabled)
                .onTapGesture { taps += 1 }
            Text("A plain Text: nothing to select")
        }
    }
}

@MainActor
private func textSelectionLog() -> some Element {
    ScrollView {
        Text(verbatim: textSelectionLogText(lines: 1_200))
            .font(size: 11)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

@MainActor
private func textSelectionRoot<H: ElementGroup, C: ElementGroup, L: ElementGroup>(header: H, controls: C, log: L) -> some Element {
    VStack(alignment: .leading, spacing: Pixels(10)) {
        header
        controls
        log
    }
    .padding(Edges(all: Pixels(12)))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(.background)
}
