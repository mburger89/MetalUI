import Testing
import Foundation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// `ViewThatFits` over `PortableFakeWindow` and the portable text system, so Linux and Windows CI run the view's choice and
// its elision (record 217, `VF-A`..`VF-C`; the macOS-only checks are `MetalUITestingTests/ViewThatFitsWindowTests.swift`).
// An app-shaped toolbar, MetalCreator's sketch bar in miniature: rows of labelled buttons, the tools that do not fit
// carried as invisible shortcut buttons, and a greedy drag-handle at the end (`F2b`). The choice follows the width, and each
// tool's key fires **once** at every width, from the chosen row alone.

@MainActor private final class VFLog {
    var fired: [String] = []
}

private let toolKeys: [String] = ["a", "b", "c"]

/// A row showing the first `count` tools as labelled buttons and the rest as invisible shortcut buttons.
private struct ToolRow: Component {
    let count: Int
    let log: VFLog
    var content: some ElementGroup {
        HStack(spacing: Pixels(0)) {
            ForEach(0..<3) { index in
                if index < count {
                    Button("Tool \(index + 1)") { log.fired.append("row\(count):tool\(index + 1)") }
                        .keyboardShortcut(KeyEquivalent(Character(toolKeys[index])), modifiers: [])
                } else {
                    Button("") { log.fired.append("row\(count):hidden\(index + 1)") }
                        .keyboardShortcut(KeyEquivalent(Character(toolKeys[index])), modifiers: [])
                        .frame(width: Pixels(0), height: Pixels(0))
                }
            }
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }
    }
}

@MainActor private func bar(_ log: VFLog) -> some Element {
    ViewThatFits(in: .horizontal) {
        ToolRow(count: 3, log: log)
        ToolRow(count: 2, log: log)
        ToolRow(count: 1, log: log)
    }
}

private func key(_ character: String) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: character, characters: character, timestamp: 0))
}

/// The choice follows the width (3 tools wide, 1 narrow, never growing as the window narrows), the three rows all appear
/// somewhere in the sweep, and every tool key fires exactly once, from the row that is chosen: an unchosen row's shortcut
/// buttons register nothing (`VF-C`). Mutation: the elision check in `Element.prepaintGroup` deleted fires each key three
/// times at every width.
@MainActor
@Test func portableAnAppShapedToolbarChoosesByWidthAndEachKeyFiresOnce() throws {
    let log = VFLog()
    let (window, platform) = try makePortableWindow(size: 700) { bar(log) }
    window.drawFrameIfNeeded()
    var rowsSeen = Set<Int>()
    var previous = 3
    for width in stride(from: 700, through: 60, by: -40) {
        platform.simulateResize(to: Size(width: Pixels(Float(width)), height: Pixels(60)))
        window.drawFrameIfNeeded()
        log.fired = []
        platform.simulateInput(key("a"))
        let rows = log.fired.compactMap { $0.split(separator: ":").first.map(String.init) }
        #expect(log.fired.count == 1, "W = \(width): key a fires once, from one row: \(log.fired)")
        guard let first = rows.first, let count = Int(first.dropFirst(3)) else { Issue.record("no row at W = \(width): \(log.fired)"); continue }
        rowsSeen.insert(count)
        #expect(count <= previous, "W = \(width): the row never grows as the window narrows (\(count) after \(previous))")
        previous = count
        for (index, character) in toolKeys.enumerated().dropFirst() {
            log.fired = []
            platform.simulateInput(key(character))
            #expect(log.fired.count == 1, "W = \(width): key \(character) (tool \(index + 1)) fires once: \(log.fired)")
            #expect(log.fired.first?.hasPrefix("row\(count):") == true, "W = \(width): and from the chosen row: \(log.fired)")
        }
    }
    #expect(rowsSeen == [1, 2, 3], "the sweep passes every threshold: \(rowsSeen.sorted())")
}
