import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// `.focused(_:)` / `.focused(_:equals:)` on a container that is not itself focusable (`FW-A`, `FW-B`, record 365; probe
// `docs/probes/swiftui-focus-container.swift`, arms F0..F5). SwiftUI reads the container's state `true` while focus is
// within it, and a write of `true` focuses the container's first focusable descendant. PLAIN imports, the harness
// text system, no clock: the file runs on every platform.

@MainActor private final class Model {
    var pane: [Bool] = []
    var inner: [Bool] = []
    var named: [Pane?] = []
    var setPane: (Bool) -> Void = { _ in }
    var setNamed: (Pane?) -> Void = { _ in }
    var text = ""
}
private enum Pane: Hashable { case a, b }

@MainActor private func box() -> some StyledElement { Box().frame(width: Pixels(40), height: Pixels(20)) }

/// `[ VStack(.focused($pane)) { x, y, z } , outside ]` where `x` is a TextField, `y` and `z` are focusable boxes (`z`
/// bound to `inner`), and `outside` is a focusable box. Tab order: x, y, z, outside.
private struct Single: Component {
    @FocusState var pane: Bool
    @FocusState var inner: Bool
    let model: Model
    var content: some ElementGroup {
        // swiftlint:disable:next redundant_discardable_let - inside a result builder `let _ =` is a declaration; `_ =` would be a stray statement
        let _ = model.pane.append(pane)
        // swiftlint:disable:next redundant_discardable_let - inside a result builder `let _ =` is a declaration; `_ =` would be a stray statement
        let _ = model.inner.append(inner)
        // swiftlint:disable:next redundant_discardable_let - inside a result builder `let _ =` is a declaration; `_ =` would be a stray statement
        let _ = model.setPane = { [pane = $pane] in pane.wrappedValue = $0 }
        VStack {
            TextField("t", text: model.text) { [model] in model.text = $0 }
            box().focusable()
            box().focusable().focused($inner)
        }.focused($pane)
        box().focusable()
    }
}

/// Two panes bound `equals:` on one `Pane?` state.
private struct Panes: Component {
    @FocusState var pane: Pane?
    let model: Model
    var content: some ElementGroup {
        // swiftlint:disable:next redundant_discardable_let - inside a result builder `let _ =` is a declaration; `_ =` would be a stray statement
        let _ = model.named.append(pane)
        // swiftlint:disable:next redundant_discardable_let - inside a result builder `let _ =` is a declaration; `_ =` would be a stray statement
        let _ = model.setNamed = { [pane = $pane] in pane.wrappedValue = $0 }
        VStack { box().focusable(); box().focusable() }.focused($pane, equals: .a)
        VStack { box().focusable(); box().focusable() }.focused($pane, equals: .b)
    }
}

@MainActor private func open<Root: Element>(@ElementBuilder _ content: @escaping @MainActor () -> Root) throws -> TestWindow {
    let w = try TestWindow(size: Size(width: Pixels(300), height: Pixels(300)), textSystem: harnessTextSystem, content: content)
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick() }
    w.window.focus(nil)   // the first draw seated the first focusable; start unfocused
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick() }
    return w
}

@MainActor private func settle(_ w: TestWindow) {
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick() }
}

@MainActor private func focus(_ w: TestWindow, _ index: Int) {
    w.window.focus(w.window.testingTabOrder[index])
    settle(w)
}

/// **1** The container's Bool reads `true` while focus is on any descendant (a field, a bare focusable, a bound
/// focusable), `false` when it moves to an element outside or is cleared. Mutation: reconcile with the focused element's
/// own binding only (`bound` from `focusBinding(for:)`): the container never reads true.
@MainActor @Test func aContainerReadsTrueWhileFocusIsWithinIt() throws {
    let model = Model()
    let w = try open { VStack { Single(model: model) } }
    defer { withExtendedLifetime(w) {} }
    #expect(model.pane.last == false)
    for index in 0...2 {
        focus(w, index)
        #expect(model.pane.last == true, "tab index \(index): \(model.pane.suffix(3))")
    }
    #expect(model.inner.last == true, "the bound leaf reads true as before")
    focus(w, 3)
    #expect(model.pane.last == false && model.inner.last == false, "focus left the container")
    focus(w, 1)
    #expect(model.pane.last == true)
    w.window.focus(nil); settle(w)
    #expect(model.pane.last == false, "cleared")
}

/// **2** Two panes on one `Pane?`: the state reads the pane holding focus, nil outside both. Mutation: as 1.
@MainActor @Test func twoPanesReadTheirOwnValue() throws {
    let model = Model()
    let w = try open { VStack { Panes(model: model) } }
    defer { withExtendedLifetime(w) {} }
    #expect(model.named.last == .some(nil))
    focus(w, 0); #expect(model.named.last == .some(.a))
    focus(w, 1); #expect(model.named.last == .some(.a))
    focus(w, 2); #expect(model.named.last == .some(.b))
    focus(w, 3); #expect(model.named.last == .some(.b))
    w.window.focus(nil); settle(w)
    #expect(model.named.last == .some(nil))
}

/// **3** Writing `.b` / `true` focuses the container's first focusable descendant, from outside it and (probe F5) from
/// inside it on a later one; writing nil / `false` clears focus only when it is within. Mutations: refuse a write whose
/// target is not focusable (as before) — focus stays; take the last descendant instead of the first.
@MainActor @Test func writingAContainersValueFocusesItsFirstFocusableDescendant() throws {
    let model = Model()
    let w = try open { VStack { Panes(model: model) } }
    defer { withExtendedLifetime(w) {} }
    let order = w.window.testingTabOrder
    model.setNamed(.b); settle(w)
    #expect(w.window.focusedElement == order[2], "first focusable of pane b")
    #expect(model.named.last == .some(.b))
    focus(w, 3)
    model.setNamed(.b); settle(w)
    #expect(w.window.focusedElement == order[2], "from inside, on a later descendant: the first (probe F5 t2)")
    model.setNamed(.a); settle(w)
    #expect(w.window.focusedElement == order[0])
    model.setNamed(nil); settle(w)
    #expect(w.window.focusedElement == nil, "nil clears focus held inside a pane")
    focus(w, 2)
    model.setNamed(nil); settle(w)
    #expect(w.window.focusedElement == nil)
    model.setNamed(.b); settle(w)
    model.setNamed(.a); settle(w); focus(w, 1)
    w.window.focus(nil); settle(w)
    model.setNamed(nil); settle(w)
    #expect(w.window.focusedElement == nil)
}

/// **3b** `false` written while focus is outside the container leaves it alone (probe F5 t4).
@MainActor @Test func falseWrittenWhileFocusIsOutsideLeavesFocusAlone() throws {
    let model = Model()
    let w = try open { VStack { Single(model: model) } }
    defer { withExtendedLifetime(w) {} }
    focus(w, 3)
    let outside = w.window.focusedElement
    model.setPane(false); settle(w)
    #expect(w.window.focusedElement == outside && outside != nil)
    model.setPane(true); settle(w)
    #expect(w.window.focusedElement == w.window.testingTabOrder[0], "true focuses the first descendant: the field")
    model.setPane(false); settle(w)
    #expect(w.window.focusedElement == nil)
}

/// **4** Cost, literal. A steady frame and a keystroke frame of the same tree with and without the binding: equal
/// element requests, and the binding written once per focus change and not on idle frames.
/// Mutation: write the container's state on every reconcile (compare dropped): the idle frames append reads.
@MainActor private func requests(bound: Bool, keystroke: Bool) throws -> Int {
    let model = Model()
    let w = try open {
        VStack { Group2(model: model, bound: bound) }
    }
    defer { withExtendedLifetime(w) {} }
    focus(w, 0)
    w.resetFrameWork()
    if keystroke { w.typeText("a") } else { w.window.setNeedsRedraw(); w.tick() }
    return w.lastFrameWork.elementRequests
}

private struct Group2: Component {
    @FocusState var pane: Bool
    let model: Model
    let bound: Bool
    var content: some ElementGroup {
        // swiftlint:disable:next redundant_discardable_let - inside a result builder `let _ =` is a declaration; `_ =` would be a stray statement
        let _ = model.pane.append(pane)
        if bound {
            VStack { TextField("t", text: model.text) { [model] in model.text = $0 }; box().focusable() }.focused($pane)
        } else {
            VStack { TextField("t", text: model.text) { [model] in model.text = $0 }; box().focusable() }
        }
    }
}

@MainActor @Test func aContainerBindingCostsNoRequestAndOneWritePerChange() throws {
    let steadyWithout = try requests(bound: false, keystroke: false)
    let steadyWith = try requests(bound: true, keystroke: false)
    // The one extra request is the `.focused` modifier's own element, which it was before this lane; the reconcile
    // walk over the focus chain adds none (literals, master's 4 and 5).
    #expect(steadyWithout == 4 && steadyWith == 5, "steady: without \(steadyWithout), with \(steadyWith)")
    let keyWithout = try requests(bound: false, keystroke: true)
    let keyWith = try requests(bound: true, keystroke: true)
    #expect(keyWith == keyWithout + 1, "keystroke: without \(keyWithout), with \(keyWith)")
    #expect(keyWithout == 4, "keystroke, without: \(keyWithout)")

    // Frames a focus change drives, then an idle forced frame: a state written once per change draws one settling
    // frame, and an unchanged focus writes nothing.
    func frames(bound: Bool, _ step: (TestWindow) -> Void) throws -> Int {
        let model = Model()
        let w = try open { VStack { Group2(model: model, bound: bound) } }
        defer { withExtendedLifetime(w) {} }
        focus(w, 0)
        let before = w.framesDrawn
        step(w)
        return w.framesDrawn - before
    }
    let idleWith = try frames(bound: true) { w in w.window.setNeedsRedraw(); w.tick(); w.tick(); w.tick() }
    let idleWithout = try frames(bound: false) { w in w.window.setNeedsRedraw(); w.tick(); w.tick(); w.tick() }
    #expect(idleWith == idleWithout && idleWith == 1, "an idle redraw is one frame: \(idleWith) vs \(idleWithout)")
    // Moving inside the container does not change the container's value: no settling frame beyond a bare move's.
    let moveWith = try frames(bound: true) { w in w.window.focus(w.window.testingTabOrder[1]); w.tick(); w.tick(); w.tick() }
    let moveWithout = try frames(bound: false) { w in w.window.focus(w.window.testingTabOrder[1]); w.tick(); w.tick(); w.tick() }
    #expect(moveWith == moveWithout, "a move within the container: \(moveWith) vs \(moveWithout)")
    // Leaving it writes the state once: exactly one frame more than without.
    let leaveWith = try frames(bound: true) { w in w.window.focus(nil); w.tick(); w.tick(); w.tick() }
    let leaveWithout = try frames(bound: false) { w in w.window.focus(nil); w.tick(); w.tick(); w.tick() }
    #expect(leaveWith == leaveWithout + 1, "leaving writes the binding once: \(leaveWith) vs \(leaveWithout)")
}
