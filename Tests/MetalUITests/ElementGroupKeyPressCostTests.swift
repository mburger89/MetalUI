import Testing
import Foundation
import Metal
import MetalUICore
import MetalUITesting
import MetalUIPlatform
@testable import MetalUI

// A steady frame's cost of `onKeyPress` on a group (ruling `KF-AD`, record 319). On a proposal chain, and on a
// `LifecycleScope` over one, the five spellings used to wrap the receiver in a `KeyboardModifier`, an `Element`
// entered (and counted in `FrameWork.elementRequests`) on every frame; they now add one `LayoutModifier.keyboard`
// layer to the chain, which costs no request. Red before: the "with" count is one (or three) above the "without".

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func kd(_ c: String) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: [], isRepeat: false, timestamp: 0))
}

@MainActor private final class CostLog { var log: [String] = [] }

/// Element requests of a steady frame: three redraws of the root, then the last one's count.
@MainActor private func steadyRequests<R: Element>(_ content: @escaping @MainActor () -> R) throws -> Int {
    let w = try TestWindow(size: Size(width: Pixels(200), height: Pixels(200))) { content() }
    defer { withExtendedLifetime(w) {} }
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
    return w.lastFrameWork.elementRequests
}

/// **1** (Alloy's shape, literal). `VStack{…}.frame(…).onChange(of:…){…}` with and without `.onKeyPress(.escape)`:
/// equal element requests on a steady frame. Mutation: have the chain's `_foldingKeyboardLayer` wrap in a
/// `KeyboardModifier` again (or drop the `_KeyPressFolding` overloads): +1.
@MainActor @Test func onKeyPressAfterAFrameAndOnChangeCostsNoRequest() throws {
    let without = try steadyRequests { VStack { Box() }.frame(width: px(50), height: px(50)).onChange(of: 1) { } }
    let with = try steadyRequests {
        VStack { Box() }.frame(width: px(50), height: px(50)).onChange(of: 1) { }.onKeyPress(.escape) { .handled }
    }
    #expect(without > 0 && with == without, "without \(without), with \(with)")
}

/// **2** (`nativeFrame`: a long chain of the plain `.frame` is ambiguous between its legacy and proposal spellings for
/// the solver, and a test must pick the proposal chain). Three chained handlers: still no request (they join one layer). Mutation: add a layer per call to
/// `addingKeyPress` instead of joining (a layer costs no request, so this is pinned by test 4's one-layer check).
@MainActor @Test func threeChainedHandlersCostNoRequest() throws {
    let without = try steadyRequests { VStack { Box() }.nativeFrame(width: px(50), height: px(50)).onChange(of: 1) { } }
    let with = try steadyRequests {
        VStack { Box() }.nativeFrame(width: px(50), height: px(50)).onChange(of: 1) { }
            .onKeyPress(.escape) { .ignored }.onKeyPress(.return) { .ignored }.onKeyPress("a") { .ignored }
    }
    #expect(with == without, "without \(without), with \(with)")
}

/// **3** Without a scope: a bare chain, one handler and five spellings.
@MainActor @Test func onKeyPressDirectlyOnAProposalChainCostsNoRequest() throws {
    let without = try steadyRequests { VStack { Box() }.nativeFrame(width: px(50), height: px(50)) }
    let with = try steadyRequests {
        VStack { Box() }.nativeFrame(width: px(50), height: px(50))
            .onKeyPress(.escape) { .ignored }
            .onKeyPress(.return, phases: .down) { _ in .ignored }
            .onKeyPress(keys: [.upArrow]) { _ in .ignored }
            .onKeyPress(characters: .letters) { _ in .ignored }
            .onKeyPress { _ in .ignored }
    }
    #expect(with == without, "without \(without), with \(with)")
}

/// **4** The fold returns the receiver's own type, so the chain stays one `ModifiedContent` however many handlers.
@MainActor @Test func theFoldReturnsTheReceiversType() {
    let scope = VStack { Box() }.frame(width: px(50), height: px(50)).onChange(of: 1) { }
    func same<T>(_ a: T, _ b: T.Type) -> Bool { true }
    #expect(same(scope.onKeyPress(.escape) { .handled }.onKeyPress("a") { .handled }, type(of: scope)))
    // One expression of two calls once resolved ambiguously (the fold and `KeyboardModifier`'s own spelling).
    let twice = VStack { Box() }.nativeFrame(width: px(50), height: px(50))
        .onKeyPress(.escape) { .ignored }.onKeyPress(.return) { .ignored }
    #expect(same(twice, ModifiedContent<VStack<LegacyContent<Box<EmptyGroup>>>, LayoutModifier>.self))
}

// MARK: routing

@MainActor private func foldWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200, content: content)
    window.drawFrameIfNeeded()
    let order = window.lastFocusRegistry.tabOrder
    try #require(order.count == 1, "set up: one focusable element, got \(order.count)")
    window.focus(order[0])
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// **5** (`KF-C`, ancestor first). A folded handler on the chain around a focused descendant hears the key before the
/// descendant's own handler; `.ignored` lets the descendant hear it; the later-written of two on the layer runs first.
/// Mutation: register the keyboard layer's handlers on no node (nothing heard).
@MainActor @Test func aFoldedHandlerRunsBeforeTheFocusedDescendantsAndTheLaterWrittenRunsFirst() throws {
    let m = CostLog()
    let (window, platform) = try foldWindow {
        VStack {
            Box().frame(width: px(20), height: px(20)).focusable()
                .onKeyPress("q") { m.log.append("inner"); return .handled }
        }.frame(width: px(100), height: px(100)).onChange(of: 1) { }
            .onKeyPress("q") { m.log.append("first"); return .ignored }
            .onKeyPress("q") { m.log.append("second"); return .ignored }
    }
    defer { withExtendedLifetime(window) {} }
    #expect(platform.simulateInput(kd("q")))
    #expect(m.log == ["second", "first", "inner"], "\(m.log)")
}

/// **6** (`KF-AD` item 2) A folded handler does not make the chain focusable. Mutation: set `isFocusable` on the
/// layer's handlers (a second tab stop).
@MainActor @Test func aFoldedHandlerDoesNotMakeTheChainFocusable() throws {
    let (window, _) = try makeFakeWindowOnDefaultDevice(size: 200) {
        VStack { Box().frame(width: px(20), height: px(20)) }.frame(width: px(100), height: px(100))
            .onKeyPress("q") { .handled }
    }
    defer { withExtendedLifetime(window) {} }
    window.drawFrameIfNeeded()
    #expect(window.lastFocusRegistry.tabOrder.isEmpty)
}

/// **7** (`KF-AD` item 3) `.focusable()` written after the fold takes the folded handlers into its `KeyboardModifier`
/// (the focus target), as one layer did before the fold; the focused chain hears its own key, in either order.
/// Mutation: delete the absorption in `KeyboardModifier.requestProposalLayout` (the layer sits inside the focus
/// target and nothing is heard).
@MainActor @Test func aKeyboardModifierWrittenOverAFoldedChainOwnsItsHandlers() throws {
    let m = CostLog()
    let (window, platform) = try foldWindow {
        VStack { Box().frame(width: px(20), height: px(20)) }.frame(width: px(100), height: px(100))
            .onKeyPress("q") { m.log.append("q"); return .handled }
            .focusable()
            .onKeyPress("w") { m.log.append("w"); return .handled }
    }
    defer { withExtendedLifetime(window) {} }
    #expect(platform.simulateInput(kd("q")) && platform.simulateInput(kd("w")))
    #expect(m.log == ["q", "w"], "\(m.log)")
}

/// **8** A legacy chain under a scope (`Box().frame(…).environment(…)`, a `StyledElement` by `ES-A` forwarding) never
/// paid: its `onKeyPress` is the `StyledElement` one, on the chain's own layer. Pinned so the fold's overloads do not
/// take it. (A `ForEach` or `Pair` receiver, with no chain to join, still takes `KF-AC`'s one layer and its one node.)
@MainActor @Test func aLegacyChainUnderAScopeCostsNoRequest() throws {
    let without = try steadyRequests { VStack { Box().frame(width: px(20), height: px(20)).environment(\.legibilityWeight, .bold) } }
    let with = try steadyRequests {
        VStack { Box().frame(width: px(20), height: px(20)).environment(\.legibilityWeight, .bold).onKeyPress(.escape) { .ignored } }
    }
    #expect(without > 0 && with == without, "without \(without), with \(with)")
}
