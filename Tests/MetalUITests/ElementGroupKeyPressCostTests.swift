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

// MARK: generic context (`KF-AE`, record 321)

private struct GroupBar: Component, Equatable {
    nonisolated static func == (a: GroupBar, b: GroupBar) -> Bool { true }
    var content: some ElementGroup { Box().frame(width: Pixels(10), height: Pixels(10)) }
}

private extension ElementGroup {
    /// Alloy's `codeKeyHandlers`: three `onKeyPress` calls inside an `extension ElementGroup`, where overload
    /// resolution sees only `ElementGroup` (the fold's and the proposal spellings are not candidates).
    @MainActor func codeKeyHandlers(_ log: CostLog) -> some ElementGroup {
        self.onKeyPress(keys: ["f"], phases: .down) { _ in log.log.append("f"); return .handled }
            .onKeyPress(.escape, phases: [.down, .repeat]) { _ in log.log.append("esc"); return .handled }
            .onKeyPress(.return, phases: .down) { _ in log.log.append("ret"); return .ignored }
    }
}

private struct StepCounts: Equatable {
    var requests = 0, ineligible = 0, hits = 0, misses = 0
}

@MainActor private func steadyCounts<R: ElementGroup>(_ content: @escaping @MainActor () -> R) throws -> StepCounts {
    let w = try TestWindow(size: Size(width: Pixels(200), height: Pixels(200))) { Box { content() } }
    defer { withExtendedLifetime(w) {} }
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
    let f = w.lastFrameWork
    return StepCounts(requests: f.elementRequests, ineligible: f.retainedIneligible,
                      hits: f.retainedHits, misses: f.retainedMisses)
}

/// **9** (`KF-AE`, Alloy shape 1). `….onChange ×3.accessibilityElement(children: .contain).accessibilityIdentifier(…)`
/// with and without a generic helper chaining three `onKeyPress` calls: the same counts on a steady frame.
/// Mutation: make `AccessibilityModifier`'s `_addingKeyPress` wrap (the protocol default) and the helper adds one request.
@MainActor @Test func aGenericHelperOverAnAccessibilityChainCostsNoRequest() throws {
    let log = CostLog()
    func base() -> some ProposalElementGroup {
        VStack { Box() }.nativeFrame(width: px(50), height: px(50))
            .onChange(of: 1, initial: true) { }.onChange(of: 1) { }.onChange(of: 2) { }
            .accessibilityElement(children: .contain).accessibilityIdentifier("file-panel")
    }
    let without = try steadyCounts { base() }
    let with = try steadyCounts { base().codeKeyHandlers(log) }
    #expect(without.requests > 0 && with == without, "without \(without), with \(with)")
}

/// **10** (`KF-AE`, Alloy shape 2). The chain holds an `OverlayModifier` over an `.equatable()` component (not a
/// proposal group), as the receiver and under a lifecycle scope. Mutation: `OverlayModifier` keeps the default.
@MainActor @Test func aGenericHelperOverAnOverlayCostsNoRequest() throws {
    let log = CostLog()
    func base() -> some ElementGroup {
        VStack { Box() }.nativeFrame(width: px(50), height: px(50))
            .accessibilityElement(children: .contain).accessibilityIdentifier("file-panel")
            .overlay { GroupBar().equatable() }
    }
    func scoped() -> some ElementGroup { base().onChange(of: 1) { } }
    let without = try steadyCounts { base() }
    let with = try steadyCounts { base().codeKeyHandlers(log) }
    #expect(without.requests > 0 && with == without, "overlay: without \(without), with \(with)")
    let withoutScope = try steadyCounts { scoped() }
    let withScope = try steadyCounts { scoped().codeKeyHandlers(log) }
    #expect(withScope == withoutScope, "scope over overlay: without \(withoutScope), with \(withScope)")
}

/// **11** The generic helper over a bare chain, a scope over a chain and a `ForEach`-less plain group: the fold
/// cases cost nothing; a `Pair` receiver (no chain, no handler slot) is not measured here.
@MainActor @Test func aGenericHelperOverAChainAndAScopeCostsNoRequest() throws {
    let log = CostLog()
    let without = try steadyCounts { VStack { Box() }.nativeFrame(width: px(50), height: px(50)) }
    let with = try steadyCounts { VStack { Box() }.nativeFrame(width: px(50), height: px(50)).codeKeyHandlers(log) }
    #expect(with == without, "chain: without \(without), with \(with)")
    let w2 = try steadyCounts { VStack { Box() }.nativeFrame(width: px(50), height: px(50)).onChange(of: 1) { } }
    let h2 = try steadyCounts {
        VStack { Box() }.nativeFrame(width: px(50), height: px(50)).onChange(of: 1) { }.codeKeyHandlers(log)
    }
    #expect(h2 == w2, "scope: without \(w2), with \(h2)")
}

/// **12** A legacy (`StyledElement`) chain, and a lifecycle scope over one, in generic code: no request either (the
/// chain's own `_addingKeyPress` joins its outermost layer; the default's wrapper layer flattened into it before as
/// well). Pinned as a guard for the chain's `ModifierLayer` hook; a mutation of it shows in test 13's types.
@MainActor @Test func aGenericHelperOverAStyledElementCostsNoRequest() throws {
    let log = CostLog()
    let without = try steadyCounts { Box().frame(width: px(20), height: px(20)) }
    let with = try steadyCounts { Box().frame(width: px(20), height: px(20)).codeKeyHandlers(log) }
    #expect(without.requests > 0 && with == without, "styled: without \(without), with \(with)")
    let scopeWithout = try steadyCounts { Box().frame(width: px(20), height: px(20)).onAppear { } }
    let scopeWith = try steadyCounts { Box().frame(width: px(20), height: px(20)).onAppear { }.codeKeyHandlers(log) }
    #expect(scopeWith == scopeWithout, "styled scope: without \(scopeWithout), with \(scopeWith)")
}

/// Three handlers on one key from a generic helper, each logging and passing the key on.
private extension ElementGroup {
    @MainActor func orderedHandlers(_ log: CostLog) -> some ElementGroup {
        self.onKeyPress("q") { log.log.append("a"); return .ignored }
            .onKeyPress("q") { log.log.append("b"); return .ignored }
            .onKeyPress("q") { log.log.append("c"); return .ignored }
    }
}

@MainActor private func leaf(_ log: CostLog) -> some ElementGroup {
    Box().frame(width: px(20), height: px(20)).focusable().onKeyPress("q") { log.log.append("inner"); return .handled }
}

/// **13** (`KF-AE`, `KF-C`). A generic helper's handlers on an accessibility wrapper, on an overlay, and on a scope over
/// each: they hear the key before the focused descendant's, the later-written first, and are not focusable.
/// Mutation: drop the wrapper's, or the overlay's, handler registration (nothing heard).
@MainActor @Test func genericHandlersOnAnAccessibilityWrapperAndAnOverlayRouteAncestorFirst() throws {
    let want = ["c", "b", "a", "inner"]
    let ax = CostLog()
    let (w1, p1) = try foldWindow { Box {
        VStack { leaf(ax) }.frame(width: px(100), height: px(100))
            .accessibilityElement(children: .contain).accessibilityIdentifier("p").orderedHandlers(ax)
    } }
    defer { withExtendedLifetime(w1) {} }
    #expect(p1.simulateInput(kd("q")))
    #expect(ax.log == want, "accessibility: \(ax.log)")
    let ov = CostLog()
    let (w2, p2) = try foldWindow { Box {
        VStack { leaf(ov) }.frame(width: px(100), height: px(100)).overlay { VStack { } }.orderedHandlers(ov)
    } }
    defer { withExtendedLifetime(w2) {} }
    #expect(p2.simulateInput(kd("q")))
    #expect(ov.log == want, "overlay: \(ov.log)")
    let sc = CostLog()
    let (w3, p3) = try foldWindow { Box {
        VStack { leaf(sc) }.frame(width: px(100), height: px(100)).accessibilityIdentifier("p").onChange(of: 1) { }
            .orderedHandlers(sc)
    } }
    defer { withExtendedLifetime(w3) {} }
    #expect(p3.simulateInput(kd("q")))
    #expect(sc.log == want, "scope: \(sc.log)")
}

/// **14** (`KF-AE` item 4, as `KF-AD` item 3) A `.focusable()` written over a wrapper or overlay that holds
/// `onKeyPress` handlers takes them (it is the focus target); they hear the focused wrapper's own key.
/// Mutation: delete `takeKeyPresses` of the wrapper (a handler inside the focus target is not on the focus chain).
@MainActor @Test func aKeyboardModifierOverAnAccessibilityWrapperOrOverlayOwnsItsHandlers() throws {
    let a = CostLog()
    let (w1, p1) = try foldWindow {
        VStack { Box().frame(width: px(20), height: px(20)) }.frame(width: px(100), height: px(100))
            .accessibilityIdentifier("p").onKeyPress("q") { a.log.append("q"); return .handled }.focusable()
    }
    defer { withExtendedLifetime(w1) {} }
    #expect(p1.simulateInput(kd("q")))
    #expect(a.log == ["q"], "accessibility: \(a.log)")
    let o = CostLog()
    let (w2, p2) = try foldWindow {
        VStack { Box().frame(width: px(20), height: px(20)) }.frame(width: px(100), height: px(100))
            .overlay { VStack { } }.onKeyPress("q") { o.log.append("q"); return .handled }.focusable()
    }
    defer { withExtendedLifetime(w2) {} }
    #expect(p2.simulateInput(kd("q")))
    #expect(o.log == ["q"], "overlay: \(o.log)")
}

@MainActor private func keyPressedInGenericCode<G: ElementGroup>(_ group: G) -> some ElementGroup {
    group.onKeyPress("a") { .handled }.onKeyPress("b") { .handled }
}

/// **15** (`KF-AE`) In generic code a chain, a scope over one and an accessibility wrapper come back as their own
/// type (no wrapper layer, no prefix absorbed), and a group with no layer is still wrapped. Mutation: a conformer
/// left on the default (`ModifiedContent`'s `_addingKeyPress` renamed, as the legacy wrapper's `_wrap` flattens a
/// chain and costs no request, only this type check shows it).
@MainActor @Test func genericOnKeyPressReturnsTheReceiversOwnTypeWhereItOwnsALayer() {
    let chain = VStack { Box() }.nativeFrame(width: px(50), height: px(50))
    #expect(type(of: keyPressedInGenericCode(chain)) == type(of: chain))
    let scope = chain.onChange(of: 1) { }
    #expect(type(of: keyPressedInGenericCode(scope)) == type(of: scope))
    let ax = chain.accessibilityIdentifier("x")
    #expect(type(of: keyPressedInGenericCode(ax)) == type(of: ax))
    let legacy = Box().frame(width: px(20), height: px(20))
    #expect(type(of: keyPressedInGenericCode(legacy)) == type(of: legacy))
    let pair = Pair(Box(), Box())
    #expect(type(of: keyPressedInGenericCode(pair)) != type(of: pair))
}
