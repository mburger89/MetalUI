import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// `onKeyPress` on any `ElementGroup` (ruling `KF-AC`, record 316). A helper that
// returns `some ElementGroup` — here `Box().environment(…)`, a scope that is an
// `ElementGroup` and neither a `StyledElement` nor a `ProposalElementGroup` —
// takes the five SwiftUI spellings. Windows are 200 × 200 over
// `FakePlatformWindow`; keys go in through `simulateInput`. Nothing sleeps.
// Red before: does not compile (`value of type … has no member 'onKeyPress'`).

private func kd(_ c: String, characters: String? = nil) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: characters ?? c, modifiers: [],
                      isRepeat: false, timestamp: 0))
}

private func ku(_ c: String) -> InputEvent {
    .keyUp(KeyEvent(charactersIgnoringModifiers: c, characters: c, timestamp: 0))
}

@MainActor private final class EGLog { var log: [String] = [] }

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// A plain `ElementGroup` helper holding one focusable element, the way an
/// app's `some ElementGroup` helper does. `descendant` is what the focused
/// element answers (`nil`: it has no handler).
@MainActor private func plainGroup(_ m: EGLog, descendant: KeyPress.Result?) -> some ElementGroup {
    let leaf = Box().frame(width: px(20), height: px(20)).focusable()
    let wrapped = descendant.map { answer in
        leaf.onKeyPress { _ in m.log.append("inner"); return answer }
    }
    return Box { wrapped ?? leaf }.environment(\.legibilityWeight, .bold)
}

@MainActor private func egWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200, content: content)
    window.drawFrameIfNeeded()
    let order = window.lastFocusRegistry.tabOrder
    try #require(order.count == 1, "set up: one focusable element, got \(order.count)")
    window.focus(order[0])
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// **1** (`KF-AC` item 1; SwiftUI: `onKeyPress` on a non-focusable view hears
/// a key its focused descendant did not handle). The group's handler runs
/// when the focused descendant has no handler. Mutation: have the group
/// spelling drop its handler (`keyPressLayer()` alone).
@MainActor
@Test func aPlainGroupsOnKeyPressHearsAKeyItsFocusedDescendantDoesNotHandle() throws {
    let m = EGLog()
    let (window, platform) = try egWindow {
        Box { plainGroup(m, descendant: nil).onKeyPress("q") { m.log.append("group"); return .handled } }
    }
    defer { withExtendedLifetime(window) {} }
    #expect(platform.simulateInput(kd("q")), "the group's handler claims q")
    #expect(m.log == ["group"], "\(m.log)")
}

/// **2** (`KF-C`: outermost first). The group's handler is an ancestor of the
/// focused element, so it runs **before** the descendant's: an ancestor that
/// handles the key shadows the descendant. A group that `.ignored`s lets the
/// descendant hear it. Mutation: register the layer's handlers on no node.
@MainActor
@Test func aPlainGroupsHandlerRunsBeforeTheDescendantsAndAnIgnoreLetsItThrough() throws {
    let handled = EGLog()
    let (w1, p1) = try egWindow {
        Box { plainGroup(handled, descendant: .ignored)
            .onKeyPress("q") { handled.log.append("group"); return .handled } }
    }
    defer { withExtendedLifetime(w1) {} }
    #expect(p1.simulateInput(kd("q")))
    #expect(handled.log == ["group"], "a handled ancestor shadows the descendant: \(handled.log)")

    let ignored = EGLog()
    let (w2, p2) = try egWindow {
        Box { plainGroup(ignored, descendant: .handled)
            .onKeyPress("q") { ignored.log.append("group"); return .ignored } }
    }
    defer { withExtendedLifetime(w2) {} }
    #expect(p2.simulateInput(kd("q")), "the descendant claims it")
    #expect(ignored.log == ["group", "inner"], "\(ignored.log)")
}

/// **3** Another key the descendant handles is not offered a second time and
/// a key nobody wants is not claimed: the group's filter is honoured.
/// Mutation: make the `.key` filter match every key.
@MainActor
@Test func aPlainGroupsKeyFilterIgnoresOtherKeys() throws {
    let m = EGLog()
    let (window, platform) = try egWindow {
        Box { plainGroup(m, descendant: nil).onKeyPress("q") { m.log.append("group"); return .handled } }
    }
    defer { withExtendedLifetime(window) {} }
    #expect(!platform.simulateInput(kd("z")), "z is not q")
    #expect(m.log.isEmpty, "\(m.log)")
}

/// **4** (K2v, `KF-AC`). Each of the five spellings routes when it is the **first** modifier
/// on the plain group (the one that reaches the `ElementGroup` overload; what
/// follows is the returned layer's own `StyledElement` spelling): `_:action:`,
/// `_:phases:action:` (a release), `keys:phases:action:`,
/// `characters:phases:action:` and `phases:action:`, each hearing what it
/// filters for and nothing else. Mutations (each shown red): `phases: phases`
/// to `.down` in the `_:phases:` spelling; `keys: keys` to `[.escape]`;
/// `characters: characters` to `.letters`; the `_:` spelling's key to `"z"`.
@MainActor
@Test func eachOfTheFiveSpellingsRoutesOnAPlainGroup() throws {
    /// Sends `events` to a window whose plain group wears one spelling; returns
    /// what the handler heard and what the window reported per event.
    func heard<Root: ElementGroup>(_ events: [InputEvent],
                                   _ spelling: @escaping @MainActor (EGLog) -> Root) throws -> ([String], [Bool]) {
        let m = EGLog()
        let (window, platform) = try egWindow { Box { spelling(m) } }
        defer { withExtendedLifetime(window) {} }
        let results = events.map { platform.simulateInput($0) }
        return (m.log, results)
    }
    let up = String(KeyEquivalent.upArrow.character)
    // `_:action:` hears a, not b.
    var r = try heard([kd("a"), kd("b")]) { m in
        plainGroup(m, descendant: nil).onKeyPress("a") { m.log.append("key"); return .handled } }
    #expect(r.0 == ["key"] && r.1 == [true, false], "\(r)")
    // `_:phases:action:` with `.up` hears the release only.
    r = try heard([kd("b"), ku("b")]) { m in
        plainGroup(m, descendant: nil).onKeyPress("b", phases: .up) { _ in m.log.append("up"); return .handled } }
    #expect(r.0 == ["up"] && r.1 == [false, true], "\(r)")
    // `keys:phases:action:` hears its set.
    r = try heard([kd(up), kd("a")]) { m in
        plainGroup(m, descendant: nil).onKeyPress(keys: [.upArrow]) { _ in m.log.append("keys"); return .handled } }
    #expect(r.0 == ["keys"] && r.1 == [true, false], "\(r)")
    // `characters:phases:action:` hears digits, not letters.
    r = try heard([kd("7"), kd("a")]) { m in
        plainGroup(m, descendant: nil).onKeyPress(characters: .decimalDigits) { _ in m.log.append("chars"); return .handled } }
    #expect(r.0 == ["chars"] && r.1 == [true, false], "\(r)")
    // `phases:action:` hears every key down, and not the release by default.
    r = try heard([kd("x"), ku("x")]) { m in
        plainGroup(m, descendant: nil).onKeyPress { press in m.log.append("any:\(press.characters)"); return .handled } }
    #expect(r.0 == ["any:x"] && r.1 == [true, false], "\(r)")
}

// MARK: - Existing conformers keep their overload

@MainActor private func accept<T>(_ value: T, as type: T.Type) {}

/// **5** (`KF-AC` item 3). A type that is also an `ElementGroup` keeps its more
/// specific overload: `StyledElement` returns `Self`, `ProposalElementGroup`
/// returns `KeyboardModifier<Self>`, a `KeyboardModifier` returns `Self`, a
/// legacy `ModifiedElement` chain returns `Self` (one layer), and only a
/// plain group returns `ModifiedElement<Self>`. Each `accept` is a compile-
/// time assertion: a changed choice does not compile. Mutation: change the
/// new overloads' return type to `Self`-less (`KeyboardModifier<…>`) or make a
/// conformer's overload ambiguous by adding the spelling to `Element`.
@MainActor
@Test func existingConformersKeepTheirOverload() throws {
    let styled = Box().onKeyPress("a") { .handled }
    accept(styled, as: Box.self)
    let padded = Box().padding(1).onKeyPress("a") { .handled }
    accept(padded, as: ModifiedElement<Box<EmptyGroup>>.self)
    let proposal = MetalView { _ in }.onKeyPress("a") { .handled }
    accept(proposal, as: KeyboardModifier<MetalView>.self)
    let again = proposal.onKeyPress("b") { .handled }
    accept(again, as: KeyboardModifier<MetalView>.self)
    plainGroupKeepsItsWrapper(Box().environment(\.legibilityWeight, .bold))
}

@MainActor private func plainGroupKeepsItsWrapper<G: ElementGroup>(_ group: G) {
    let plain = group.onKeyPress("a") { .handled }
    // `KF-AE`: the result is the conformer's own `KeyPressed` (a scope over a `StyledElement` is itself).
    accept(plain, as: G.KeyPressed.self)
    accept(plain.onKeyPress("b") { .handled }, as: G.KeyPressed.KeyPressed.self)
    // A group with no layer of its own still takes one wrapper, and a second spelling joins it (a StyledElement).
    let pair = Pair(Box(), Box())
    accept(pair.onKeyPress("a") { .handled }, as: ModifiedElement<Pair<Box<EmptyGroup>, Box<EmptyGroup>>>.self)
    accept(pair.onKeyPress("a") { .handled }.onKeyPress("b") { .handled },
           as: ModifiedElement<Pair<Box<EmptyGroup>, Box<EmptyGroup>>>.self)
}
