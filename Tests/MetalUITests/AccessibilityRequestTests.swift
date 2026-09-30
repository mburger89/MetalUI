import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 12 part 2, lane 2 (spec `2026-09-29-accessibility-design.md` §6,
// §7, tests 2.20, 2.22–2.24; rulings `IX-V` item 2, `IX-Y`, `IX-Z` items 2–3):
// the dispatch of a press and a custom action through a real `Window` on a
// `FakePlatformWindow`. Helpers are `ButtonTests.swift`'s `control…`; every
// window is kept alive to the test's end (`IX-AG` item 8: the fake holds its
// window weakly, so a discarded window refuses for the wrong reason).

private typealias Request = MetalUIPlatform.AccessibilityRequest

@MainActor private final class Log {
    var lines: [String] = []
    var shown = false
}

/// **2.20.** A press runs a declared action INSTEAD of the element's click (A4:
/// `["Default"]`, while a mouse click still runs the button's own action), and
/// over a tap runs the action, not the tap (G6) — on both spellings. Mutation
/// M2t (the hitbox tried first) must redden it.
@Test @MainActor func anAccessibilityPressRunsADeclaredActionInsteadOfTheClick() throws {
    let log = Log()
    let (window, platform) = try controlWindow(size: 300) {
        controlRoot(width: 300, height: 300) {
            Button("B") { log.lines.append("B") }.accessibilityAction { log.lines.append("Default") }
            Text("Tap").onTapGesture { log.lines.append("tap") }.accessibilityAction { log.lines.append("action") }
        }
    }
    let tree = try controlTree(window, platform)
    try withExtendedLifetime(window) {
        let b = try tree.one("B").id
        #expect(platform.simulateAccessibilityRequest(.press(b)))
        #expect(log.lines == ["Default"], "A4: the declared action, not the button's: \(log.lines)")
        let bID = try #require(b.base as? GlobalElementID)
        let bounds = try #require(window.lastElementBounds[bID])
        controlClick(platform, at: controlCentre(bounds))
        #expect(log.lines == ["Default", "B"], "a click still runs the button's own action: \(log.lines)")

        log.lines = []
        #expect(platform.simulateAccessibilityRequest(.press(try tree.one("Tap").id)))
        #expect(log.lines == ["action"], "G6 legacy: the action, not the tap: \(log.lines)")
    }

    let proposalLog = Log()
    let (proposal, proposalPlatform) = try controlWindow(size: 300) {
        HStack { ProposalText("Tap").onTapGesture { proposalLog.lines.append("tap") }
            .accessibilityAction { proposalLog.lines.append("action") } }
    }
    let proposalTree = try controlTree(proposal, proposalPlatform)
    let tap = try proposalTree.one("Tap").id
    withExtendedLifetime(proposal) {
        #expect(proposalPlatform.simulateAccessibilityRequest(.press(tap)))
        #expect(proposalLog.lines == ["action"], "G6 proposal: \(proposalLog.lines)")
    }
}

/// **2.22.** A combined element's press runs its first interactive child's
/// (E6: `B`; E14: `A`), and custom action `i` runs the `i`-th's (E14: 1 → `B`,
/// 0 → `A`). Mutation M2v (custom action `i` runs redirect 0) must redden it.
@Test @MainActor func aCombinedElementsPressAndCustomActionsRunItsInteractiveChildren() throws {
    let log = Log()
    let (window, platform) = try controlWindow(size: 300) {
        controlRoot(width: 300, height: 300) {
            Column { Text("E6"); Button("B6") { log.lines.append("B6") } }.accessibilityElement(children: .combine)
            Column { Button("A") { log.lines.append("A") }; Button("B") { log.lines.append("B") } }
                .accessibilityElement(children: .combine)
        }
    }
    let tree = try controlTree(window, platform)
    try withExtendedLifetime(window) {
        let e6 = try tree.one("E6, B6").id
        #expect(platform.simulateAccessibilityRequest(.press(e6)))
        #expect(log.lines == ["B6"], "E6: \(log.lines)")

        log.lines = []
        let e14 = try tree.one("A").id
        #expect(platform.simulateAccessibilityRequest(.press(e14)))
        #expect(platform.simulateAccessibilityRequest(.customAction(e14, 1)))
        #expect(platform.simulateAccessibilityRequest(.customAction(e14, 0)))
        #expect(log.lines == ["A", "B", "A"], "E14: press A, custom 1 B, custom 0 A: \(log.lines)")
        #expect(!platform.simulateAccessibilityRequest(.customAction(e14, 2)), "no third action")
    }

    // E17/E18p/E20 (probe revision 2, `IX-AI`): beside a slider or a text
    // field the press runs the first child that PRESSES whatever the order,
    // and an increment reaches the slider — SwiftUI's `["A", "S0.6"]` in both
    // orders, and E20's `["A"]`.
    let mixedLog = Log()
    let slider = Binding<Double>(get: { 0.5 }, set: { mixedLog.lines.append("S\($0 > 0.5 ? "+" : "-")") })
    let (mixed, mixedPlatform) = try controlWindow(size: 300) {
        controlRoot(width: 300, height: 300) {
            Column { Button("P") { mixedLog.lines.append("P") }; Slider(value: slider) }
                .accessibilityElement(children: .combine)
            Column { Slider(value: slider); Button("Q") { mixedLog.lines.append("Q") } }
                .accessibilityElement(children: .combine)
            Column { TextField("F", text: .constant("x")); Button("R") { mixedLog.lines.append("R") } }
                .accessibilityElement(children: .combine)
        }
    }
    let mixedTree = try controlTree(mixed, mixedPlatform)
    try withExtendedLifetime(mixed) {
        for name in ["P", "Q"] {
            mixedLog.lines = []
            let node = try mixedTree.one(name).id
            #expect(mixedPlatform.simulateAccessibilityRequest(.press(node)), "\(name): press")
            #expect(mixedPlatform.simulateAccessibilityRequest(.increment(node)), "\(name): increment")
            #expect(mixedLog.lines == [name, "S+"], "\(name): the button presses, the slider adjusts: \(mixedLog.lines)")
        }
        // E20: a text field first — the press still reaches the button.
        mixedLog.lines = []
        #expect(mixedPlatform.simulateAccessibilityRequest(.press(try mixedTree.one("R").id)), "E20: press")
        #expect(mixedLog.lines == ["R"], "E20: the button, not the field: \(mixedLog.lines)")
    }
}

/// **2.23.** A custom action request runs the node's named handler (A2), a
/// button keeps its own press beside it (A3), later-written names come first
/// (A6: 0 → `Two`, 1 → `One`), and an index past the list is refused. Mutation
/// M2w (the index read from the end) must redden it.
@Test @MainActor func aCustomActionRequestRunsTheNamedHandlerAndABadIndexNothing() throws {
    let log = Log()
    let (window, platform) = try controlWindow(size: 300) {
        controlRoot(width: 300, height: 300) {
            Text("T").accessibilityAction(named: "Delete") { log.lines.append("Delete") }
            Button("B") { log.lines.append("B") }.accessibilityAction(named: "Archive") { log.lines.append("Archive") }
            Text("Six").accessibilityAction(named: "One") { log.lines.append("One") }
                .accessibilityAction(named: "Two") { log.lines.append("Two") }
        }
    }
    let tree = try controlTree(window, platform)
    try withExtendedLifetime(window) {
        #expect(platform.simulateAccessibilityRequest(.customAction(try tree.one("T").id, 0)))
        #expect(log.lines == ["Delete"], "A2: \(log.lines)")

        log.lines = []
        let b = try tree.one("B").id
        #expect(platform.simulateAccessibilityRequest(.press(b)))
        #expect(platform.simulateAccessibilityRequest(.customAction(b, 0)))
        #expect(log.lines == ["B", "Archive"], "A3: \(log.lines)")
        #expect(!platform.simulateAccessibilityRequest(.customAction(b, 5)), "index 5 is refused")
        #expect(log.lines == ["B", "Archive"], "and runs nothing")

        log.lines = []
        let six = try tree.one("Six").id
        #expect(platform.simulateAccessibilityRequest(.customAction(six, 0)))
        #expect(platform.simulateAccessibilityRequest(.customAction(six, 1)))
        #expect(log.lines == ["Two", "One"], "A6: \(log.lines)")
    }
}

/// **2.24.** When the published tree was built under modal isolation, a request
/// for an element outside it — one a client already holds — is refused and runs
/// nothing (divergence 95; SwiftUI's held element presses, M5); with the modal
/// gone it presses. Mutation M2x (the refusal removed) must redden it.
@Test @MainActor func aRequestForAnElementOutsideTheModalIsRefused() throws {
    let log = Log()
    let (window, platform) = try controlWindow(size: 300) {
        controlRoot(width: 300, height: 300) {
            Stack {
                Button("Under") { log.lines.append("Under") }
                if log.shown {
                    Column { Button("Top") {} }.accessibilityAddTraits(.isModal)
                }
            }
        }
    }
    let open = try controlTree(window, platform)
    try withExtendedLifetime(window) {
        let under = try open.one("Under").id
        log.shown = true
        controlRedraw(window)
        controlRedraw(window)
        let covered = try #require(platform.publishedAccessibilityTrees.last)
        #expect(covered.readings == ["Top"], "the modal isolates: \(covered.readings)")
        #expect(!platform.simulateAccessibilityRequest(.press(under)), "M5: the held element is refused")
        #expect(log.lines.isEmpty, "and runs nothing: \(log.lines)")

        log.shown = false
        controlRedraw(window)
        controlRedraw(window)
        #expect(platform.simulateAccessibilityRequest(.press(under)), "the modal gone: it presses")
        #expect(log.lines == ["Under"], "\(log.lines)")
    }
}
