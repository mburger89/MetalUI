import Testing
import Foundation
import Metal
import MetalUICore
import MetalUITesting
import MetalUIPlatform
@testable import MetalUI

// A steady keystroke frame's cost of `keyCapture(except:optionAsMeta:)` (ruling `TRM-Y`, record 338), in the style of
// `ElementGroupKeyPressCostTests`. `keyCapture` adds a marker handler to the layer an `onKeyPress` joins: no element,
// no layout node, no registration beyond one dictionary entry, so an app not using it pays nothing (its counts equal
// master's) and one using it pays no request either. The literals are measured; the "without" ones on master
// `ff73af7c` and on this branch (equal).

private func px(_ v: Float) -> Pixels { Pixels(v) }

private struct Counts: Equatable, CustomStringConvertible {
    var requests = 0, hits = 0, misses = 0, ineligible = 0
    var description: String { "requests \(requests), hits \(hits), misses \(misses), ineligible \(ineligible)" }
}

/// Counts of the frame a keystroke draws after the window is steady: three redraws, then an unhandled `z` and its frame.
@MainActor private func keystrokeFrame<R: Element>(_ content: @escaping @MainActor () -> R) throws -> Counts {
    let w = try TestWindow(size: Size(width: px(200), height: px(200))) { content() }
    defer { withExtendedLifetime(w) {} }
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
    let order = w.window.lastFocusRegistry.tabOrder
    try #require(order.count == 1, "set up: one focusable element, got \(order.count)")
    w.window.focus(order[0])
    for _ in 0..<2 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
    w.send(.keyDown(KeyEvent(charactersIgnoringModifiers: "z", characters: "z", timestamp: 0)))
    w.advance(by: 0.05)
    let f = w.lastFrameWork
    return Counts(requests: f.elementRequests, hits: f.retainedHits, misses: f.retainedMisses,
                  ineligible: f.retainedIneligible)
}

@MainActor private func plain() -> some Element {
    Box { Box { Box().frame(width: px(20), height: px(20)).focusable() }.onKeyPress { _ in .ignored } }
}

@MainActor private func capturing() -> some Element {
    Box { Box { Box().frame(width: px(20), height: px(20)).focusable() }.onKeyPress { _ in .ignored }.keyCapture() }
}

@MainActor private func capturingWithOption() -> some Element {
    Box { Box { Box().frame(width: px(20), height: px(20)).focusable() }.onKeyPress { _ in .ignored }
        .keyCapture(except: [KeyboardShortcut("c")], optionAsMeta: true) }
}

/// **C1** An app that does not use `keyCapture`: the keystroke frame's counts, literal (equal to master's).
/// Mutation: make `Window.syncRawOptionKeys` or the registry's capture entry cost a request (none is expected: the
/// literal moves only with a real change in the frame path).
@MainActor @Test func aKeystrokeFrameWithoutKeyCaptureCostsWhatMasterCosts() throws {
    let c = try keystrokeFrame { plain() }
    #expect(c == Counts(requests: 3, hits: 0, misses: 0, ineligible: 0), "\(c)")
}

/// **C2** An app using `keyCapture` (and one using every parameter): the same literal. Mutation: have `keyCapture`
/// wrap the receiver in a `KeyboardModifier` (+1 request).
@MainActor @Test func aKeystrokeFrameWithKeyCaptureCostsNoMore() throws {
    let c = try keystrokeFrame { capturing() }
    #expect(c == Counts(requests: 3, hits: 0, misses: 0, ineligible: 0), "\(c)")
    let o = try keystrokeFrame { capturingWithOption() }
    #expect(o == c, "every parameter: \(o) vs \(c)")
}

/// **C3** On a proposal chain `keyCapture` joins the one keyboard layer as `onKeyPress` does: no more requests than
/// the chain with the handler alone, and the same with the capture written before or after it. (The chain is spelled
/// inline: behind an opaque `some ProposalElementGroup` the fold's overloads are not candidates.) Mutation: make
/// `_KeyPressFolding.keyCapture` wrap in a `KeyboardModifier` instead of folding.
@MainActor @Test func keyCaptureOnAProposalChainCostsNoRequest() throws {
    let without = try keystrokeFrame {
        Box { VStack { Box().frame(width: px(20), height: px(20)).focusable() }.nativeFrame(width: px(50), height: px(50))
            .onKeyPress { _ in .ignored } }
    }
    let with = try keystrokeFrame {
        Box { VStack { Box().frame(width: px(20), height: px(20)).focusable() }.nativeFrame(width: px(50), height: px(50))
            .onKeyPress { _ in .ignored }.keyCapture() }
    }
    let first = try keystrokeFrame {
        Box { VStack { Box().frame(width: px(20), height: px(20)).focusable() }.nativeFrame(width: px(50), height: px(50))
            .keyCapture().onKeyPress { _ in .ignored } }
    }
    #expect(without == Counts(requests: 4, hits: 0, misses: 0, ineligible: 0), "without \(without)")
    #expect(with == without && first == without, "without \(without), with \(with), capture first \(first)")
}
