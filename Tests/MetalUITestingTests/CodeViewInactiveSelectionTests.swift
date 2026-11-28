import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// `CodeTheme.inactiveSelection` (`CV-BB`, record 331): a view draws `selection` while it is the focused element of a
// key window and `inactiveSelection` otherwise. Painted rectangles are told apart by alpha: the theme's two colours
// carry alphas no other fill in the view has. PLAIN imports; the harness text system.

private let activeAlpha: Float = 0.31
private let inactiveAlpha: Float = 0.17

@MainActor private func viewOf(_ buffer: CodeBuffer, _ decorations: CodeDecorations, state: CodeSelectionState?) -> CodeView {
    var view = CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
    if let state { view = view.selectionState(state) }
    return view
}

@MainActor private func marked(_ decorations: CodeDecorations) {
    decorations.theme.selection = Color(red: 0, green: 0, blue: 1).opacity(Double(activeAlpha))
    decorations.theme.inactiveSelection = Color(red: 1, green: 0, blue: 0).opacity(Double(inactiveAlpha))
}

/// Two split views of one buffer, each with its own state and a one-row selection, A the left 200 points, B the right.
@MainActor private final class Split {
    let window: TestWindow
    let stateA: CodeSelectionState, stateB: CodeSelectionState
    let buffer = CodeBuffer("hello world\nsecond line\n")

    init() async throws {
        let buffer = self.buffer
        let decoA = CodeDecorations(buffer: buffer), decoB = CodeDecorations(buffer: buffer)
        marked(decoA); marked(decoB)
        let stateA = CodeSelectionState(buffer: buffer), stateB = CodeSelectionState(buffer: buffer)
        self.stateA = stateA; self.stateB = stateB
        window = try harnessWindow(size: sz(400, 100)) {
            HStack(spacing: 0) {
                viewOf(buffer, decoA, state: stateA)
                viewOf(buffer, decoB, state: stateB)
            }
        }
        stateA.selections = [CodeSelection(anchor: 0, head: 5)]
        stateB.selections = [CodeSelection(anchor: 0, head: 5)]
        try await frame()
    }
    func frame() async throws { window.window.setNeedsRedraw(); try await window.runUntilIdle() }
    /// A press in the first row of A (`false`) or B; it collapses that view's selection, so the range is set again.
    func focus(_ b: Bool) async throws {
        window.click(at: pt((b ? 200 : 0) + 120, 6))
        (b ? stateB : stateA).selections = [CodeSelection(anchor: 0, head: 5)]
        try await frame()
    }
    /// The selection rectangles painted in the left (`false`) or right half, by kind: (active, inactive).
    func painted(_ b: Bool) -> (active: Int, inactive: Int) {
        let rects = window.scene.rects.filter { ($0.bounds.origin.x >= 200) == b }
        return (rects.filter { abs($0.background.a - activeAlpha) < 0.001 }.count,
                rects.filter { abs($0.background.a - inactiveAlpha) < 0.001 }.count)
    }
}

/// **1** A view that is not the focused element draws the inactive selection (the first focusable view is focused
/// at the start, so B is the unfocused one, then A after the press in B). **Mutation:** painting `theme.selection`
/// unconditionally gives (1, 0).
@Test @MainActor func anUnfocusedViewPaintsTheInactiveSelection() async throws {
    let s = try await Split()
    defer { withExtendedLifetime(s) {} }
    #expect(s.painted(true) == (0, 1), "B beside a focused A: \(s.painted(true))")
    try await s.focus(true)
    #expect(s.painted(false) == (0, 1), "A beside a focused B: \(s.painted(false))")
}

/// **2** The focused view draws `selection`, the other still the inactive one. **Mutation:** choosing `inactiveSelection`
/// always gives (0, 1) for A.
@Test @MainActor func theFocusedViewPaintsTheSelection() async throws {
    let s = try await Split()
    defer { withExtendedLifetime(s) {} }
    try await s.focus(false)
    #expect(s.painted(false) == (1, 0), "A \(s.painted(false))")
    #expect(s.painted(true) == (0, 1), "B \(s.painted(true))")
}

/// **3** Focus moving between two split views swaps the colours. **Mutation:** deciding by "some view has focus" instead
/// of this view's id leaves both views active after the first press.
@Test @MainActor func focusMovingBetweenSplitViewsSwapsTheColours() async throws {
    let s = try await Split()
    defer { withExtendedLifetime(s) {} }
    try await s.focus(false)
    #expect(s.painted(false).active == 1 && s.painted(true).inactive == 1)
    try await s.focus(true)
    #expect(s.painted(false) == (0, 1), "A after B took focus: \(s.painted(false))")
    #expect(s.painted(true) == (1, 0), "B: \(s.painted(true))")
}

/// **4** A window that is not key draws the focused view's selection inactive, and key again restores it. **Mutation:**
/// dropping the `controlActiveState` test from the choice keeps it active.
@Test @MainActor func aWindowThatIsNotKeyPaintsTheInactiveSelection() async throws {
    let s = try await Split()
    defer { withExtendedLifetime(s) {} }
    try await s.focus(false)
    s.window.setControlActiveState(.inactive)
    #expect(s.painted(false) == (0, 1), "inactive window: \(s.painted(false))")
    s.window.setControlActiveState(.active)
    #expect(s.painted(false) == (0, 1), ".active is not key: \(s.painted(false))")
    s.window.setControlActiveState(.key)
    #expect(s.painted(false) == (1, 0), "key again: \(s.painted(false))")
}

/// **5** The default values are the probe's `unemphasizedSelectedTextBackgroundColor`: #DCDCDC in light, #464646 in
/// dark (`appkit-inactive-selection.swift`); the focused default is untouched. **Mutation:** another grey fails.
@Test @MainActor func theDefaultInactiveSelectionIsAppKitsUnemphasizedColour() async throws {
    let theme = CodeTheme()
    #expect(theme.inactiveSelection == Color(light: Color(hex: 0xDCDCDC), dark: Color(hex: 0x464646)))
    #expect(theme.selection == Color.accentColor.opacity(0.3))
    #expect(CodeTheme.defaultInactiveSelection == theme.inactiveSelection)
    #expect(CodeTheme(selection: .red).inactiveSelection == theme.inactiveSelection, "an existing initialiser call keeps the default")
    // Painted through the window's scheme.
    let buffer = CodeBuffer("hello\n")
    let decorations = CodeDecorations(buffer: buffer)
    let w = try harnessWindow(size: sz(220, 50)) {
        HStack(spacing: 0) {   // the box takes the initial focus
            Color.gray.frame(width: Pixels(20), height: Pixels(20)).focusable()
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off)
        }
    }
    defer { withExtendedLifetime(w) {} }
    buffer.selections = [CodeSelection(anchor: 0, head: 5)]
    w.window.setNeedsRedraw(); try await w.runUntilIdle()
    w.click(at: pt(10, 25))   // the box has the focus
    func selectionFill() async throws -> Float? {
        w.window.setNeedsRedraw(); try await w.runUntilIdle()
        let narrow = w.scene.rects.filter { (r: MUIRect) -> Bool in r.bounds.size.width < 100 && r.bounds.size.width > 25 }
        return narrow.first?.background.l
    }
    w.setAppearance(.light)
    let light = try #require(try await selectionFill())
    w.setAppearance(.dark)
    let dark = try #require(try await selectionFill())
    #expect(abs(light - Float(0xDC) / 255) < 0.02 && abs(dark - Float(0x46) / 255) < 0.02, "light \(light) dark \(dark) rects \(w.scene.rects.map { ($0.bounds.size.width, $0.background.l) })")
}

/// **6** A custom `inactiveSelection` is honoured, also set on a decorations' theme after creation. **Mutation:** the
/// view reading `CodeTheme()`'s default gives the grey instead of the red.
@Test @MainActor func aCustomInactiveSelectionIsHonoured() async throws {
    let buffer = CodeBuffer("hello\n")
    let decorations = CodeDecorations(buffer: buffer)
    decorations.theme = CodeTheme(selection: Color(red: 0, green: 0, blue: 1).opacity(Double(activeAlpha)),
                                  inactiveSelection: Color(red: 1, green: 0, blue: 0).opacity(Double(inactiveAlpha)))
    let w = try harnessWindow(size: sz(220, 50)) {
        HStack(spacing: 0) {   // the box takes the initial focus
            Color.gray.frame(width: Pixels(20), height: Pixels(20)).focusable()
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off)
        }
    }
    defer { withExtendedLifetime(w) {} }
    buffer.selections = [CodeSelection(anchor: 0, head: 5)]
    w.window.setNeedsRedraw(); try await w.runUntilIdle()
    w.click(at: pt(10, 25))   // the box has the focus
    w.window.setNeedsRedraw(); try await w.runUntilIdle()
    #expect(w.scene.rects.filter { abs($0.background.a - inactiveAlpha) < 0.001 }.count == 1, "\(w.scene.rects.map { ($0.bounds, $0.background) })")
    decorations.theme.inactiveSelection = Color(red: 0, green: 1, blue: 0).opacity(0.23)
    w.window.setNeedsRedraw(); try await w.runUntilIdle()
    #expect(w.scene.rects.filter { abs($0.background.a - 0.23) < 0.001 }.count == 1, "a theme change repaints")
}

// MARK: Steady-frame cost

private struct Card: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    let decorations: CodeDecorations
    var content: some ElementGroup { viewOf(buffer, decorations, state: nil) }
    static func == (l: Card, r: Card) -> Bool { l.buffer === r.buffer && l.decorations === r.decorations }
}

private struct Steady: Equatable { var requests = 0, hits = 0, misses = 0, ineligible = 0 }

/// One steady frame of `views` retained code views with a selection; `focused` presses the first view first.
@MainActor private func steady(views: Int, focused: Bool) async throws -> Steady {
    let buffer = CodeBuffer(codeText(lines: 60))
    let decorations = (0..<views).map { _ in CodeDecorations(buffer: buffer) }
    let w = try harnessWindow(size: sz(400, 200)) {
        HStack(spacing: 0) {
            Box().frame(width: Pixels(20), height: Pixels(20)).focusable()
            ForEach(0..<views, id: \.self) { i in
                Card(buffer: buffer, decorations: decorations[i]).equatable().frame(width: Pixels(180), height: Pixels(150))
            }
        }
    }
    defer { withExtendedLifetime(w) {} }
    if focused { w.click(at: pt(60, 6)) }
    buffer.selections = [CodeSelection(anchor: 0, head: 5)]
    for _ in 0..<4 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    w.resetFrameWork()
    w.window.setNeedsRedraw(); try await w.runUntilIdle()
    let f = totalWork(w)
    return Steady(requests: f.elementRequests, hits: f.retainedHits, misses: f.retainedMisses, ineligible: f.retainedIneligible)
}

/// **7** A steady frame costs what it did on master c625d565 (literals measured there), unfocused and focused: choosing
/// the colour adds no element, no observation and no retention taint. **Mutation:** adding an
/// extra wrapper element (`.padding(1)` around the view) adds a request per view (4 becomes 5).
@Test @MainActor func aSteadyFrameCostsWhatItDidBeforeInactiveSelection() async throws {
    let one = try await steady(views: 1, focused: false), two = try await steady(views: 2, focused: false)
    #expect(one == Steady(requests: 3, hits: 1, misses: 0, ineligible: 0), "\(one)")
    #expect(two == Steady(requests: 4, hits: 2, misses: 0, ineligible: 0), "\(two)")
    let oneFocused = try await steady(views: 1, focused: true), twoFocused = try await steady(views: 2, focused: true)
    #expect(oneFocused == Steady(requests: 3, hits: 1, misses: 0, ineligible: 0), "\(oneFocused)")
    #expect(twoFocused == Steady(requests: 4, hits: 2, misses: 0, ineligible: 0), "\(twoFocused)")
}

/// **8** A focus change repaints the two views concerned and no other: of three retained views, moving the focus from
/// the first to the second leaves the third a retention hit. **Mutation:** a colour choice that taints retention makes
/// the third miss.
@Test @MainActor func aFocusChangeLeavesAnUnconcernedViewRetained() async throws {
    let buffer = CodeBuffer(codeText(lines: 60))
    let decorations = (0..<3).map { _ in CodeDecorations(buffer: buffer) }
    let w = try harnessWindow(size: sz(600, 200)) {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                Card(buffer: buffer, decorations: decorations[i]).equatable().frame(width: Pixels(200), height: Pixels(150))
            }
        }
    }
    defer { withExtendedLifetime(w) {} }
    w.click(at: pt(60, 6))
    for _ in 0..<4 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    w.resetFrameWork()
    w.click(at: pt(260, 6))
    let f = totalWork(w)
    #expect(f.retainedHits >= 1, "the third view hit: hits \(f.retainedHits) misses \(f.retainedMisses) ineligible \(f.retainedIneligible)")
}
