import Testing
import Foundation
import Observation
import MetalUI
import MetalUIScene
import MetalUITesting

// `.restoresFocusOnDismiss()` (`KF-AM`) and a popover's implicit scope (`MN-AS`). PLAIN imports, the harness text
// system, no clock: the file runs on every platform. Probe F2 (`focusDropsWhenAnIfRemovesItsElement`): SwiftUI drops
// focus and does not restore it; this scope is MetalUI's addition, and the popover half matches AppKit's NSPopover.

@Observable @MainActor private final class Model {
    var showScope = true      // the scope itself is produced
    var showField = true      // the field inside it
    var showA = true          // the element focus comes from
    var restores = true
    var text: [String: String] = [:]
    var fieldBinding: (String) -> Binding<String> {
        { name in Binding(get: { self.text[name] ?? "" }, set: { self.text[name] = $0 }) }
    }
}

private enum Spot: Hashable { case a, b }

/// `A`, `B` outside; the scope holds `F`. The shape is chosen by `scopeOutside`: the scope wraps an `if` (the scope stays,
/// probe F2) or sits inside one (the scope goes with its content).
private struct Page: Component {
    let model: Model
    let scopeStays: Bool
    var useFocusState = false
    @FocusState var spot: Spot?
    @FocusState var pane: Bool
    var content: some ElementGroup {
        VStack(spacing: 4) {
            VStack(spacing: 4) {
                if model.showA {
                    TextField("a", text: model.fieldBinding("a")).accessibilityIdentifier("A").focused($spot, equals: .a)
                        .frame(width: Pixels(100), height: Pixels(24))
                }
                TextField("b", text: model.fieldBinding("b")).accessibilityIdentifier("B").focused($spot, equals: .b)
                    .frame(width: Pixels(100), height: Pixels(24))
            }.focused($pane)
            if scopeStays {
                VStack(spacing: 0) {
                    if model.showField {
                        TextField("f", text: model.fieldBinding("f")).accessibilityIdentifier("F")
                            .frame(width: Pixels(100), height: Pixels(24))
                    }
                }.restoresFocusOnDismiss(model.restores)
            } else if model.showScope {
                VStack(spacing: 0) {
                    TextField("f", text: model.fieldBinding("f")).accessibilityIdentifier("F")
                        .frame(width: Pixels(100), height: Pixels(24))
                }.restoresFocusOnDismiss(model.restores)
            }
            Button("dismiss") { model.showScope = false; model.showField = false; if useFocusState { spot = .b } }
                .accessibilityIdentifier("dismiss").frame(width: Pixels(80), height: Pixels(24))
            Text(pane ? "pane" : "nopane")
            Text(spot == .a ? "spotA" : spot == .b ? "spotB" : "spotNil")
            Spacer(minLength: 0)
        }
    }
}

@MainActor private func page(_ model: Model, scopeStays: Bool = false, focusState: Bool = false) throws -> TestWindow {
    let w = try harnessWindow(size: sz(300, 300)) {
        VStack(spacing: 0) { Page(model: model, scopeStays: scopeStays, useFocusState: focusState) }
    }
    settle(w)
    w.window.focus(nil)
    settle(w)
    return w
}

@MainActor private func settle(_ w: TestWindow) {
    for _ in 0..<4 { w.window.setNeedsRedraw(); w.tick() }
}

@MainActor private func focused(_ w: TestWindow) throws -> String? { try w.focusedElement?.identifier }

@MainActor private func click(_ w: TestWindow, _ id: String) throws {
    try w.click(try w.element(identifier: id))
    w.tick()
}

/// The state readouts the page draws as text: which of the candidate strings is on screen.
@MainActor private func label(_ w: TestWindow, _ id: String) throws -> String {
    let candidates = id == "spot" ? ["spotA", "spotB", "spotNil"] : ["pane", "nopane"]
    return candidates.first { (try? w.element(label: $0)) != nil } ?? "none"
}

/// **No scope: the drop is today's.** Probe F2 pinned for a tree with this fixture's shape: the `if` removes the focused
/// field and focus is `nil`, whatever was focused before. Mutation: restore at every drop (drop the scope check and the
/// record lookup in `Frame.dropFocus`) and `A` is focused here.
@Test @MainActor func noScopeFocusDropUnchanged() throws {
    let model = Model()
    model.restores = false   // the modifier present but off is no scope
    let w = try page(model)
    try click(w, "A"); try click(w, "F")
    let inside = try focused(w)
    #expect(inside == "F")
    model.showScope = false
    settle(w)
    let after = try focused(w)
    #expect(after == nil, "focus drops to nil and does not return (F2)")
}

/// The scope removed with its focused field: focus returns to the element focused when it entered the scope.
/// **Mutation:** `dropFocus` clearing without the restore leaves `nil`.
@Test @MainActor func ifRemovalRestoresToPrevious() throws {
    let model = Model()
    let w = try page(model)
    try click(w, "A"); try click(w, "F")
    let inside = try focused(w)
    #expect(inside == "F")
    model.showScope = false
    settle(w)
    let now = try focused(w)
    #expect(now == "A", "focus returned to A: \(String(describing: now))")
    w.typeText("z")
    #expect(model.text["a"] == "z", "and typing lands in it")
}

/// Removing only the field while the scope stays keeps today's drop (probe F2). **Mutation:** drop the
/// "scope was produced this frame" check and `A` is focused.
@Test @MainActor func removingOnlyTheElementWhileTheScopeStaysDrops() throws {
    let model = Model()
    let w = try page(model, scopeStays: true)
    try click(w, "A"); try click(w, "F")
    model.showField = false
    settle(w)
    let after = try focused(w)
    #expect(after == nil, "the scope stayed, so this is the F2 drop")
}

/// The recorded element is gone by the dismissal: focus is `nil`, as today (Alloy's answer 9). **Mutation:** skip the
/// `isFocusable` check on the target and focus is set to a dead id the next frame clears, reading `A` for a frame.
@Test @MainActor func targetGoneLeavesNil() throws {
    let model = Model()
    let w = try page(model)
    try click(w, "A"); try click(w, "F")
    model.showA = false
    model.showScope = false
    w.window.setNeedsRedraw(); w.tick()   // the one frame that drops: its answer is already nil, not a dead id
    #expect(w.window.focusedElement == nil, "no dead id is handed back for the next frame to clear")
    settle(w)
    let gone = try focused(w)
    #expect(gone == nil)
    let spot = try label(w, "spot")
    #expect(spot == "spotNil")
}

/// A `@FocusState` write applied in the same transaction as the removal wins: there is no drop, so nothing restores.
/// **Mutation:** restore regardless of who moved focus (use the record even when the hand-in focus is not the dropped
/// element) and focus ends on `A`.
@Test @MainActor func writeInSameTransactionWins() throws {
    let model = Model()
    let w = try page(model, focusState: true)
    try click(w, "A"); try click(w, "F")
    try click(w, "dismiss")   // removes the scope and writes `spot = .b` in one handler
    settle(w)
    let now = try focused(w)
    #expect(now == "B", "the write wins: \(String(describing: now))")
}

/// Leaving the scope and entering it again records the latest outside element, not the first. **Mutation:** drop the
/// discard of a left scope's record and record only when none exists (both lines of `noteRestoreTransition`), and `A` comes back.
@Test @MainActor func leavingScopeByClickDiscardsRecord() throws {
    let model = Model()
    let w = try page(model)
    try click(w, "A"); try click(w, "F")
    try click(w, "B")
    try click(w, "F")
    model.showScope = false
    settle(w)
    let now = try focused(w)
    #expect(now == "B", "the record is the last entry's: \(String(describing: now))")
}

/// Nested scopes restore the innermost. **Mutation:** record in the outermost scope only and the first dismissal lands
/// on `A`.
@Observable @MainActor private final class Nest {
    var inner = true
    var outer = true
}
private struct Nested: Component {
    let nest: Nest
    var content: some ElementGroup {
        VStack(spacing: 4) {
            TextField("a", text: .constant("")).accessibilityIdentifier("A").frame(width: Pixels(100), height: Pixels(24))
            if nest.outer {
                VStack(spacing: 4) {
                    TextField("g", text: .constant("")).accessibilityIdentifier("G").frame(width: Pixels(100), height: Pixels(24))
                    if nest.inner {
                        VStack(spacing: 0) {
                            TextField("f", text: .constant("")).accessibilityIdentifier("F").frame(width: Pixels(100), height: Pixels(24))
                        }.restoresFocusOnDismiss()
                    }
                }.restoresFocusOnDismiss()
            }
            Spacer(minLength: 0)
        }
    }
}
@Test @MainActor func nestedScopesRestoreInnermost() throws {
    let nest = Nest()
    let w = try harnessWindow(size: sz(300, 300)) { VStack(spacing: 0) { Nested(nest: nest) } }
    settle(w); w.window.focus(nil); settle(w)
    try click(w, "A"); try click(w, "G"); try click(w, "F")
    nest.inner = false
    settle(w)
    let first = try focused(w)
    #expect(first == "G", "the inner scope restores to G: \(String(describing: first))")
    nest.outer = false
    settle(w)
    let second = try focused(w)
    #expect(second == "A", "then the outer one to A: \(String(describing: second))")
}

/// A tree with no `@FocusState`: the restore is the only thing that can ask for the frame that paints the ring.
@Observable @MainActor private final class Plain { var show = true; var restores = true }
private struct PlainPage: Component {
    let plain: Plain
    var content: some ElementGroup {
        VStack(spacing: 4) {
            TextField("a", text: .constant("")).accessibilityIdentifier("A").frame(width: Pixels(100), height: Pixels(24))
            if plain.show {
                VStack(spacing: 0) {
                    TextField("f", text: .constant("")).accessibilityIdentifier("F").frame(width: Pixels(100), height: Pixels(24))
                }.restoresFocusOnDismiss(plain.restores)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The restore costs one extra frame (its ring), then the window is idle; a plain drop costs none.
/// **Mutation:** no `requestAnotherFrame()` in `dropFocus` and the restore frame count equals the drop's.
@Test @MainActor func restoreCostsOneExtraFrame() throws {
    func frames(restores: Bool) throws -> (Int, String?) {
        let plain = Plain(); plain.restores = restores
        let w = try harnessWindow(size: sz(300, 300)) { VStack(spacing: 0) { PlainPage(plain: plain) } }
        settle(w); w.window.focus(nil); settle(w)
        try click(w, "A"); try click(w, "F")
        settle(w)
        let before = w.framesDrawn
        plain.show = false
        for _ in 0..<6 { w.tick() }
        return (w.framesDrawn - before, try focused(w))
    }
    let (restoreFrames, restored) = try frames(restores: true)
    let (dropFrames, dropped) = try frames(restores: false)
    #expect(restored == "A" && dropped == nil)
    #expect(restoreFrames == dropFrames + 1, "restore \(restoreFrames) vs drop \(dropFrames)")
}

/// `@FocusState` reads the restored value, a container binding included (`FW-A`): after the restore `spot == .a` and the
/// container around `A` and `B` reads `true`; while `F` had focus it read `false`. **Mutation:** reconcile before the
/// restore settles and the labels keep the old values.
@Test @MainActor func focusStateReadsRestoredValue() throws {
    let model = Model()
    let w = try page(model)
    try click(w, "A"); try click(w, "F")
    settle(w)
    let before = (try label(w, "spot"), try label(w, "pane"))
    #expect(before == ("spotNil", "nopane"))
    model.showScope = false
    settle(w)
    let after = (try label(w, "spot"), try label(w, "pane"))
    #expect(after.0 == "spotA", "the element's own state: \(after.0)")
    #expect(after.1 == "pane", "the container's state (FW-A)")
}

// MARK: - Popover (`MN-AS`)

private struct Pick: Identifiable { let id: Int }

@Observable @MainActor private final class PopModel {
    var item: Pick?
    var viewKeys: [String] = []
    var text = ""
    var itemBinding: Binding<Pick?> { Binding(get: { self.item }, set: { self.item = $0 }) }
    var textBinding: Binding<String> { Binding(get: { self.text }, set: { self.text = $0 }) }
}

private struct PopHost: Component {
    let buffer: CodeBuffer, decorations: CodeDecorations, geometry: CodeViewGeometry, model: PopModel
    var content: some ElementGroup {
        VStack(spacing: 0) {
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false)
                .codeCaretBlink(.off).geometry(geometry).accessibilityIdentifier("code")
                .onKeyPress(characters: CharacterSet(charactersIn: "a")) { press in
                    model.viewKeys.append(press.characters)
                    return .handled
                }
                .popover(item: model.itemBinding, attachmentAnchor: .caret, arrowEdge: .bottom) { _ in
                    TextField("name", text: model.textBinding).accessibilityIdentifier("pfield")
                        .frame(width: Pixels(120), height: Pixels(24))
                }
                .frame(width: Pixels(400), height: Pixels(200))
            Spacer(minLength: 0)
        }
    }
}

/// A text-anchored popover with a field, dismissed with Escape: focus returns to the `CodeView` that had it when focus
/// entered the popover (AppKit: the presenter's first responder never changed). **Mutation:** drop the implicit scope in
/// `PopoverModifier.prepaint` and focus is `nil` after the dismissal (the `IX-I` drop).
@Test @MainActor func dismissingAPopoverReturnsFocusToThePresenter() async throws {
    let model = PopModel()
    let buffer = CodeBuffer("let a = 1\nlet b = 2\n")
    let decorations = CodeDecorations(buffer: buffer)
    let geometry = CodeViewGeometry()
    let window = try harnessWindow(size: sz(400, 300)) {
        VStack(spacing: 0) { PopHost(buffer: buffer, decorations: decorations, geometry: geometry, model: model) }
    }
    window.window.setNeedsRedraw()
    window.tick(); window.tick()
    window.click(at: Point(x: Pixels(60), y: Pixels(6)))   // the view has focus
    let presenter = try window.focusedElement?.identifier
    #expect(presenter == "code", "the view is focused: \(String(describing: presenter))")
    model.item = Pick(id: 1)
    window.window.setNeedsRedraw(); window.tick(); window.tick()
    try window.click(try window.element(identifier: "pfield"))
    let inField = try window.focusedElement?.identifier
    #expect(inField == "pfield")
    window.typeKey(.escape)
    try await window.runUntilIdle()
    #expect(model.item == nil)
    let back = try window.focusedElement?.identifier
    #expect(back == "code", "focus returned to the view: \(String(describing: back))")
    window.typeText("a")
    #expect(model.viewKeys == ["a"], "and the view takes the keys again")
}

// MARK: - Cost (no scope anywhere)

/// An app with no restoring scope: the work of a steady frame, a keystroke frame and a focus-change frame is what it was
/// before `KF-AM` (measured on master 9dc1e9a8 and equal; per frame, off Darwin as on it).
@Test @MainActor func appsWithNoScopeCostWhatTheyCost() throws {
    let model = Model()
    let w = try harnessWindow(size: sz(300, 300)) {
        VStack(spacing: 4) {
            TextField("a", text: model.fieldBinding("a")).accessibilityIdentifier("A").frame(width: Pixels(100), height: Pixels(24))
            TextField("b", text: model.fieldBinding("b")).accessibilityIdentifier("B").frame(width: Pixels(100), height: Pixels(24))
            Spacer(minLength: 0)
        }
    }
    settle(w); w.window.focus(nil); settle(w)
    try click(w, "A")
    settle(w)
    w.resetFrameWork()
    w.window.setNeedsRedraw(); w.tick()
    let steady = w.lastFrameWork
    w.resetFrameWork()
    w.typeText("x")
    let keystroke = w.lastFrameWork
    w.resetFrameWork()
    try w.click(try w.element(identifier: "B"))
    let change = w.lastFrameWork
    // (requests, prepaints, builds) per frame; the same numbers on master 9dc1e9a8 (run there with this test alone).
    #expect([steady, keystroke, change].map { [$0.elementRequests, $0.elementPrepaints, $0.builds] } == [[5, 6, 1], [5, 6, 1], [5, 6, 1]])
}
