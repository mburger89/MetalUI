import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene
@testable import MetalUI

// Alloy gap G18 (rulings `VT-A`..`VT-H`, `docs/superpowers/2026-11-09-vertical-text-field-decisions.md`, record 255):
// `TextField(_:text:axis: .vertical)` with `lineLimit` ranges, the scroll inside it, the wheel and the keys. Every SwiftUI
// number is the probe's (`docs/probes/swiftui-vertical-text-field.swift`, arms S, R, W, K); the font is 13 pt, so a line
// is 16 points and a bordered field adds 8.

private func near(_ a: Float, _ b: Float, _ tolerance: Float = 0.01) -> Bool { abs(a - b) < tolerance }

@MainActor
private final class Draft {
    var text: String
    var submits = 0
    init(_ text: String = "") { self.text = text }
}

private func lines(_ n: Int) -> String { (1...max(n, 1)).map { "line \($0)" }.joined(separator: "\n") }

/// A vertical field showing `text` (200 wide when `width` says so).
@MainActor
private func vfield(_ text: String, placeholder: String = "") -> TextField {
    TextField(placeholder, text: text, axis: .vertical, onChange: { _ in })
}

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: Pixels(x), y: Pixels(y)) }

private func key(_ name: String, _ modifiers: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: name, characters: name, modifiers: modifiers, timestamp: 0))
}

@MainActor
private func open<E: Element>(size: Int = 400, _ make: @escaping @MainActor () -> E) throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: size, content: make)
    window.drawFrameIfNeeded()
    return (window, platform)
}

@MainActor
private func fieldHit(_ window: Window) throws -> Hitbox {
    try #require(window.lastHitboxes.first { $0.handlers.textInput != nil }, "the field's hitbox")
}

/// The height of the field `make` builds, 200 wide, proposed no height (`fixedSize` vertically): its ideal, which is the content,
/// the floor and the proposal having no say.
@MainActor
private func fieldHeight(_ make: @escaping @MainActor () -> TextField) throws -> Float {
    let (window, _) = try open {
        Box { VStack(alignment: .leading, spacing: 0) { make().frame(width: Pixels(200)).fixedSize(horizontal: false, vertical: true) } }
    }
    return try fieldHit(window).bounds.size.height.value
}

/// The same field offered the whole 400-point window height.
@MainActor
private func fieldHeightOffered400(_ make: @escaping @MainActor () -> TextField) throws -> Float {
    let (window, _) = try open { Box { VStack(alignment: .leading, spacing: 0) { make().frame(width: Pixels(200)) } } }
    return try fieldHit(window).bounds.size.height.value
}

/// The height the field answers to a 200-by-`proposal` proposal.
@MainActor
private func fieldHeight(proposal: Float, _ make: @escaping @MainActor () -> TextField) throws -> Float {
    let (window, _) = try open {
        Box { VStack(alignment: .leading, spacing: 0) { make().frame(width: Pixels(200), height: Pixels(proposal)) } }
    }
    return try fieldHit(window).bounds.size.height.value
}

// MARK: - 1-11 the height

/// **1** (`VT-B`; probe S: `lineLimit(1...8)` at 0/1/3/8/20 lines answers 24/24/56/136/136). A line is 16 points and the
/// bordered chrome adds 8.
///
/// Mutation M1: the upper bound not applied (`shown = min(shown, upper)` removed) reddens the 20-line arm.
@Test @MainActor func aVerticalFieldIsAsTallAsItsLinesBetweenTheBoundsOfLineLimit() throws {
    for (count, want) in [(0, Float(24)), (1, 24), (3, 56), (8, 136), (20, 136)] {
        let height = try fieldHeight { vfield(count == 0 ? "" : lines(count)).lineLimit(1...8) }
        #expect(height == want, "\(count) lines under 1...8: \(height)")
        let offered = try fieldHeightOffered400 { vfield(count == 0 ? "" : lines(count)).lineLimit(1...8) }
        #expect(offered == want, "\(count) lines under 1...8 offered 400 (it hugs): \(offered)")
    }
}

/// **2** (`VT-B`; probe S: no limit at 20 lines answers 328, and `lineLimit(8)` alone caps at 136).
///
/// Mutation M2: the missing upper bound defaulting to 8 reddens the 328.
@Test @MainActor func withoutALimitAVerticalFieldGrowsWithItsText() throws {
    #expect(try fieldHeight { vfield(lines(20)) } == 328)
    #expect(try fieldHeight { vfield(lines(20)).lineLimit(8) } == 136, "an upper bound alone caps like 1...8")
    #expect(try fieldHeight { vfield(lines(20)).lineLimit(...8) } == 136)
}

/// **3** (`VT-B`; probe S, the floor): a proposal under the content is answered down to the lower bound's height, and to
/// zero when there is no lower bound: 1...8 at 10 gives 24, 2...8 gives 40, `3...` gives 56, none gives 10 and a 0 proposal 0.
///
/// Mutation M3: the floor reading `?? 1` for a missing lower bound (as the content does) reddens the "no limit" arms.
@Test func theFloorIsTheLowerBoundsHeightAndNothingWithoutOne() {
    func height(_ limit: TextLineLimit, _ proposal: Double?) -> Double {
        VerticalFieldMetrics.height(displayLines: 20, lineHeight: 16, verticalInset: 4, limit: limit, proposal: proposal)
    }
    #expect(height(TextLineLimit(min: 1, max: 8), 10) == 24)
    #expect(height(TextLineLimit(min: 2, max: 8), 10) == 40)
    #expect(height(TextLineLimit(min: 3, max: nil), 10) == 56)
    #expect(height(TextLineLimit(min: nil, max: nil), 10) == 10, "no lower bound: the proposal compresses it")
    #expect(height(TextLineLimit(min: nil, max: nil), 0) == 0)
    #expect(height(TextLineLimit(min: nil, max: 8), 10) == 10, "`lineLimit(8)` has no floor")
    #expect(height(TextLineLimit(min: 1, max: 8), 1000) == 136 && height(TextLineLimit(min: 1, max: 8), nil) == 136
            && height(TextLineLimit(min: 1, max: 8), .infinity) == 136, "it hugs its content")
}

/// **4** (`VT-B`; probe S: a proposal between the floor and the content is answered exactly, 100, 80 and 70, not snapped to
/// whole lines), through the layout too.
///
/// Mutation M4: the proposal rounded down to whole lines (`(p - 2v) / lh` floored) reddens all three.
@Test @MainActor func aProposalBetweenTheFloorAndTheContentIsAnsweredExactly() throws {
    for proposal in [Float(100), 80, 70] {
        #expect(VerticalFieldMetrics.height(displayLines: 20, lineHeight: 16, verticalInset: 4,
                                            limit: TextLineLimit(min: 1, max: 8), proposal: Double(proposal)) == Double(proposal))
        #expect(try fieldHeight(proposal: proposal) { vfield(lines(20)).lineLimit(1...8) } == proposal, "\(proposal) through the layout")
    }
}

/// **5** (`VT-B`; probe S: `lineLimit(3, reservesSpace: true)` is 56 at 1 and at 20 lines, `lineLimit(8, reservesSpace: true)` at one
/// line is 136).
///
/// Mutation M5: the lower bound ignored (`shown = min(displayLines, upper)`) reddens the 1-line arms.
@Test @MainActor func reservingSpaceMakesTheFieldAlwaysThatTall() throws {
    #expect(try fieldHeight { vfield(lines(1)).lineLimit(3, reservesSpace: true) } == 56)
    #expect(try fieldHeight { vfield(lines(20)).lineLimit(3, reservesSpace: true) } == 56)
    #expect(try fieldHeight { vfield(lines(1)).lineLimit(8, reservesSpace: true) } == 136)
}

/// **6** (`VT-B`; probe S: `lineLimit(0)` acts as 1). Mutation M6: the bound's clamp to 1 removed reddens it (a zero upper
/// bound shows no line).
@Test @MainActor func aLineLimitOfZeroActsAsOne() throws {
    #expect(try fieldHeight { vfield(lines(3)).lineLimit(0) } == 24)
}

/// **7** (`VT-B`; probe S: `"a\n"` answers 40; an empty text takes its placeholder's lines, a 2-line placeholder answers 40).
///
/// Mutations M7a: the trailing-newline `+1` dropped reddens the first; M7b: the placeholder branch dropped (always the text)
/// reddens the second.
@Test @MainActor func aTrailingNewlineAndAPlaceholderCountAsLines() throws {
    #expect(try fieldHeight { vfield("a\n").lineLimit(1...8) } == 40)
    #expect(try fieldHeight { vfield("", placeholder: "one\ntwo").lineLimit(1...8) } == 40)
}

/// **8** (`VT-B`; probe S: a paragraph that wraps into 24 lines answers 136 under 1...8 and 392 without a limit). The lines are
/// the ones `TextEditor` wraps with, counted at the field's width less its insets.
///
/// Mutation M8: counting hard lines only (`text.split("\n")`) reddens both arms (one line, 24).
@Test @MainActor func aWrappedParagraphIsCappedLikeHardLines() throws {
    let paragraph = Array(repeating: "word", count: 120).joined(separator: " ")
    let capped = try fieldHeight { vfield(paragraph).lineLimit(1...8) }
    let free = try fieldHeight { vfield(paragraph) }
    #expect(capped == 136, "wrapped lines are capped: \(capped)")
    #expect(free > 136 && (free - 8).truncatingRemainder(dividingBy: 16) == 0 && free == 392, "24 wrapped lines: \(free)")
}

/// **9** (`VT-B`; probe S: the plain style is 16 per line, 16/48/128 at 1/3/8 lines, and capped at 128).
///
/// Mutation M9: the bordered insets added whatever the style reddens all of it.
@Test @MainActor func aPlainVerticalFieldHasNoChromeInsets() throws {
    for (count, want) in [(1, Float(16)), (3, 48), (8, 128)] {
        #expect(try fieldHeight { vfield(lines(count)).textFieldStyle(.plain) } == want, "\(count) lines plain")
    }
    #expect(try fieldHeight { vfield(lines(20)).textFieldStyle(.plain).lineLimit(1...8) } == 128)
}

/// **10** (`VT-B`; probe S: a horizontal field is always 24 and ignores `lineLimit`).
///
/// Mutation M10: the limit read on both axes (the vertical guard removed from the measure) reddens it.
@Test @MainActor func aHorizontalFieldIgnoresLineLimit() throws {
    #expect(try fieldHeight { TextField("", text: lines(3), onChange: { _ in }).lineLimit(1...8) } == 24)
}

/// **11** (`VT-C`; probe S: a container's `lineLimit` reaches the field; the field's own value wins over the environment's).
///
/// Mutations M11a: only the field's own value read (`ownLineLimit ?? TextLineLimit()`) reddens the container arm; M11b: only
/// the environment's read reddens the own-value arm.
@Test @MainActor func aContainersLineLimitReachesTheFieldAndTheFieldsOwnWins() throws {
    #expect(try fieldHeight { vfield(lines(5)) } == 88, "no limit: five lines")
    let (window, _) = try open {
        Box { VStack(alignment: .leading, spacing: 0) { vfield(lines(5)).frame(width: Pixels(200)).fixedSize(horizontal: false, vertical: true) }.lineLimit(1...2) }
    }
    #expect(try fieldHit(window).bounds.size.height.value == 40, "the container's 1...2 reaches it")
    let (own, _) = try open {
        Box { VStack(alignment: .leading, spacing: 0) { vfield(lines(5)).lineLimit(1...3).frame(width: Pixels(200)).fixedSize(horizontal: false, vertical: true) }.lineLimit(1...2) }
    }
    #expect(try fieldHit(own).bounds.size.height.value == 56, "its own 1...3 wins")
}

// MARK: - 12-16 the scroll

/// A 200-wide, 1...8 composer over a draft, in a 400-point window.
@MainActor
private func composer(_ draft: Draft, limit: ClosedRange<Int> = 1...8) throws -> (Window, FakePlatformWindow) {
    try open {
        Box {
            VStack(alignment: .leading, spacing: 0) {
                TextField("", text: draft.text, axis: .vertical, onChange: { draft.text = $0 })
                    .onSubmit { draft.submits += 1 }.lineLimit(limit).frame(width: Pixels(200))
            }
        }
    }
}

/// How far the focused field's content is scrolled: its content top (the bounds' y plus the 4-point inset) less line 0's.
@MainActor
private func scrollY(_ window: Window) throws -> Float {
    let hit = try fieldHit(window)
    return hit.bounds.origin.y.value + 4 - Float(try #require(hit.handlers.textInput).originY)
}

@MainActor
private func focus(_ window: Window, _ platform: FakePlatformWindow) throws {
    let hit = try fieldHit(window)
    platform.simulateInput(.mouseDown(MouseEvent(position: pt(hit.bounds.origin.x.value + 10, hit.bounds.origin.y.value + 8), clickCount: 1)))
    platform.simulateInput(.mouseUp(MouseEvent(position: pt(hit.bounds.origin.x.value + 10, hit.bounds.origin.y.value + 8))))
    window.drawFrameIfNeeded()
}

@MainActor
private func blur(_ window: Window, _ platform: FakePlatformWindow) {
    platform.simulateInput(.mouseDown(MouseEvent(position: pt(390, 390), clickCount: 1)))
    platform.simulateInput(.mouseUp(MouseEvent(position: pt(390, 390))))
    window.drawFrameIfNeeded()
}

/// **12** (`VT-D`; probe R: typing past the cap reveals the caret). A focused field of 8 lines gains four more with ⌥↩ at the
/// end: 12 lines, `scrollY = 12 * 16 - 128 = 64`. The reveal is written back, so the wheel then starts from 64 and a step
/// of 16 up leaves 48.
///
/// Mutation M12: the compared write-back skipped (`if focused && …` removed) leaves the stored scroll 0, so the wheel step
/// reddens (it starts from 0).
@Test @MainActor func typingPastTheCapRevealsTheCaretAndStoresTheScroll() throws {
    let draft = Draft(lines(8))
    let (window, platform) = try composer(draft)
    try focus(window, platform)
    platform.simulateInput(key(TextEditing.downArrow, .command))
    window.drawFrameIfNeeded()
    let fits = try scrollY(window)
    #expect(near(fits, 0), "8 lines fit: \(fits)")
    for _ in 0..<4 {
        platform.simulateInput(key("\r", .option))
        window.drawFrameIfNeeded()
    }
    #expect(draft.text == lines(8) + "\n\n\n\n")
    #expect(try fieldHit(window).bounds.size.height.value == 136, "capped at 8 lines")
    let revealed = try scrollY(window)
    #expect(near(revealed, 64), "12 lines in a 128-point viewport: \(revealed)")
    let hit = try fieldHit(window)
    platform.simulateInput(.scrollWheel(ScrollEvent(position: pt(hit.bounds.origin.x.value + 50, hit.bounds.origin.y.value + 40),
                                                    delta: pt(0, 16))))
    window.drawFrameIfNeeded()
    let stepped = try scrollY(window)
    #expect(near(stepped, 48), "the wheel starts from the stored 64: \(stepped)")
}

/// **13** (`VT-D`; probe R: ⌘↓ goes to the end, y = 320 - 128 + 4, and ⌘↑ back to the top). The viewport is the bounds less
/// both insets: a 20-line field scrolls to 20 * 16 - 128 = 192.
///
/// Mutation M13: the geometry laid out in the bounds, not the content rect, ends at 184 (off by the 8 points of inset).
@Test @MainActor func commandDownGoesToTheEndAndCommandUpBackToTheTop() throws {
    let draft = Draft(lines(20))
    let (window, platform) = try composer(draft)
    try focus(window, platform)
    platform.simulateInput(key(TextEditing.downArrow, .command)); window.drawFrameIfNeeded()
    let end = try scrollY(window)
    #expect(near(end, 192), "the end: \(end)")
    platform.simulateInput(key(TextEditing.upArrow, .command)); window.drawFrameIfNeeded()
    let start = try scrollY(window)
    #expect(near(start, 0), "the top: \(start)")
    let target = try #require(try fieldHit(window).handlers.textInput)
    #expect(near(Float(target.maxScrollY), 192), "the target carries the room: \(target.maxScrollY)")
    #expect(target.verticalField)
}

/// A scrolling column: 100 points above, the field, 800 below.
@MainActor
private func scrolledComposer(_ draft: Draft) throws -> (Window, FakePlatformWindow) {
    try open {
        Box {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(width: Pixels(200), height: Pixels(100))
                    TextField("", text: draft.text, axis: .vertical, onChange: { draft.text = $0 })
                        .lineLimit(1...8).frame(width: Pixels(200))
                    Color.clear.frame(width: Pixels(200), height: Pixels(800))
                }
            }
        }
    }
}

@MainActor
private func wheel(_ platform: FakePlatformWindow, over hit: Hitbox, _ dy: Float) {
    platform.simulateInput(.scrollWheel(ScrollEvent(position: pt(hit.bounds.origin.x.value + 50, hit.bounds.origin.y.value + 40),
                                                    delta: pt(0, dy))))
}

/// **14** (`VT-E`, `XS-F`'s one-axis rule): a focused field with room in the wheel's direction takes the wheel; at its edge, and
/// unfocused, the wheel goes on to the `ScrollView` around it. Observed by the field's own scroll and by the field's y.
///
/// Mutations M14a: the room test dropped reddens the edge arm (the field swallows the wheel at 192); M14b: the focus test
/// dropped reddens the unfocused arm (the field, with room, takes it).
@Test @MainActor func aFocusedWheelWithRoomScrollsTheFieldAndOtherwiseTheOuterScrollView() throws {
    let draft = Draft(lines(20))
    let (window, platform) = try scrolledComposer(draft)
    let y0 = try fieldHit(window).bounds.origin.y.value
    wheel(platform, over: try fieldHit(window), -30); window.drawFrameIfNeeded()
    let afterUnfocused = try fieldHit(window).bounds.origin.y.value
    #expect(afterUnfocused < y0, "an unfocused field passes the wheel on: \(y0) -> \(afterUnfocused)")
    try focus(window, platform)
    platform.simulateInput(key(TextEditing.upArrow, .command)); window.drawFrameIfNeeded()
    let y1 = try fieldHit(window).bounds.origin.y.value
    wheel(platform, over: try fieldHit(window), -30); window.drawFrameIfNeeded()
    let taken = try scrollY(window)
    #expect(near(taken, 30), "a focused field with room takes it: \(taken)")
    #expect(try fieldHit(window).bounds.origin.y.value == y1, "and the outer view stays")
    platform.simulateInput(key(TextEditing.downArrow, .command)); window.drawFrameIfNeeded()
    let y2 = try fieldHit(window).bounds.origin.y.value
    wheel(platform, over: try fieldHit(window), -30); window.drawFrameIfNeeded()
    #expect(try fieldHit(window).bounds.origin.y.value < y2, "at the end the wheel reaches the outer scroll view")
    let stays = try scrollY(window)
    #expect(near(stays, 192), "the field stays at its end: \(stays)")
}

/// **15** (`VT-E`): a `TextEditor` keeps swallowing the wheel, with room or not, focused or not (`TI-H`).
///
/// Mutation M15: the field's rule applied to the editor (`verticalField: true` on its target) reddens it (an unfocused editor with
/// no room passes the wheel on).
@Test @MainActor func aTextEditorStillSwallowsTheWheel() throws {
    let (window, platform) = try open {
        Box {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(width: Pixels(200), height: Pixels(100))
                    TextEditor("", text: "short", onChange: { _ in }).frame(width: Pixels(200), height: Pixels(100))
                    Color.clear.frame(width: Pixels(200), height: Pixels(800))
                }
            }
        }
    }
    let hit = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil })
    let y0 = hit.bounds.origin.y.value
    wheel(platform, over: hit, -30); window.drawFrameIfNeeded()
    #expect(try #require(window.lastHitboxes.first { $0.handlers.textInput != nil }).bounds.origin.y.value == y0,
            "the editor took the wheel")
}

/// **16** (`VT-D`, human check VT2): an unfocused field draws from the top and keeps its stored scroll for when it is focused again.
///
/// Mutations M16a: painting and aiming with the stored scroll (`focused: true` in the geometry) reddens the top arm; M16b: the
/// write-back not gated on focus (an unfocused frame stores its 0) reddens the stored arm.
@Test @MainActor func anUnfocusedFieldDrawsFromTheTopAndKeepsItsScroll() throws {
    let draft = Draft(lines(20))
    let (window, platform) = try open {
        Box {
            VStack(alignment: .leading, spacing: 10) {
                TextField("", text: draft.text, axis: .vertical, onChange: { draft.text = $0 }).lineLimit(1...8).frame(width: Pixels(200))
                TextField("other", text: "", onChange: { _ in }).frame(width: Pixels(200))
            }
        }
    }
    func vertical() throws -> Hitbox {
        try #require(window.lastHitboxes.first { $0.handlers.textInput?.verticalField == true })
    }
    func scrolled() throws -> Float {
        let hit = try vertical()
        return hit.bounds.origin.y.value + 4 - Float(try #require(hit.handlers.textInput).originY)
    }
    let hit = try vertical()
    platform.simulateInput(.mouseDown(MouseEvent(position: pt(hit.bounds.origin.x.value + 10, hit.bounds.origin.y.value + 8), clickCount: 1)))
    platform.simulateInput(key(TextEditing.downArrow, .command)); window.drawFrameIfNeeded()
    let end = try scrolled()
    #expect(near(end, 192), "focused, at the end: \(end)")
    let other = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil && $0.handlers.textInput?.lines == nil })
    platform.simulateInput(.mouseDown(MouseEvent(position: pt(other.bounds.origin.x.value + 10, other.bounds.origin.y.value + 8), clickCount: 1)))
    window.drawFrameIfNeeded()
    let unfocused = try scrolled()
    #expect(near(unfocused, 0), "unfocused: from the top: \(unfocused)")
    let stored = try #require(window.stateTable.peek(try vertical().id, as: TextEditState.self), "the field's edit state")
    #expect(near(Float(stored.scrollY), 192), "the stored scroll is kept through the blur: \(stored.scrollY)")
}

// MARK: - 19 TextEditor is unchanged

/// **19** (`VT-A`): `TextEditor`'s drawing is what it was before `MultilineText` was extracted (the scene of three texts, empty,
/// short and 30 lines, unfocused, focused, selected, scrolled to the end and composing, was compared byte for byte before and
/// after, record 255). Pinned here by its lines' and caret's geometry: the caret is 1 by 16 at line 1's top, the selection
/// rect starts at the line's top.
///
/// Mutation M19: every line's y shifted by 1 in `MultilineText.paintLines` reddens it.
@Test @MainActor func aTextEditorDrawsItsLinesAndCaretWhereItAlwaysDid() throws {
    let (window, platform) = try open(size: 200) { Box { TextEditor("Notes", text: "one\none") { _ in } } }
    let hit = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil })
    platform.simulateInput(.mouseDown(MouseEvent(position: pt(hit.bounds.origin.x.value + 5, hit.bounds.origin.y.value + 20), clickCount: 1)))
    platform.simulateInput(key(TextEditing.rightArrow, .shift))
    window.drawFrameIfNeeded()
    let top = hit.bounds.origin.y.value
    // The selected character on line 1 starts at that line's top and is a line tall.
    let selection = try #require(window.lastScene.rects.first {
        near($0.bounds.size.height, 16) && $0.bounds.origin.y > top + 1 && $0.bounds.size.width > 1
    }, "the selection rect")
    #expect(near(selection.bounds.origin.y, top + 16), "line 1 is one line below the top: \(selection.bounds)")
    let ys = window.lastScene.glyphs.map { $0.bounds.origin.y }
    let line0 = try #require(ys.filter { $0 < top + 16 }.min()), line1 = try #require(ys.filter { $0 >= top + 16 }.min())
    #expect(near(line1 - line0, 16), "one line apart: \(line0) \(line1)")
    #expect(line0 >= top && line0 < top + 16, "line 0 at the editor's top: \(line0) in \(hit.bounds)")
}

// MARK: - the pinned differences

/// **Divergence 237** (`VT-D`): a text replaced from code moves the caret to the end of a focused vertical field and **reveals it**
/// (`SL-P`'s caret move plus the reveal); SwiftUI moves the caret without scrolling (probe R, "replaced from code"). Pinned as
/// MetalUI's answer: 30 lines in a 128-point viewport are scrolled to 30 * 16 - 128 = 352.
@Test @MainActor func aTextReplacedFromCodeRevealsTheCaretInAVerticalField() throws {
    let draft = Draft(lines(20))
    let (window, platform) = try composer(draft)
    try focus(window, platform)
    platform.simulateInput(key(TextEditing.upArrow, .command)); window.drawFrameIfNeeded()
    let top = try scrollY(window)
    #expect(near(top, 0), "at the top: \(top)")
    draft.text = lines(30)
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let revealed = try scrollY(window)
    #expect(near(revealed, 352), "the caret at the new end is in view (SwiftUI does not scroll): \(revealed)")
}

/// **Divergence 239** (`VT-B`): `.controlSize(.small)` at 3 lines is 46 here (11 pt lines of 13 and 3.5-point insets, `CS1`);
/// SwiftUI's is 50 (probe S). Pinned wrong on purpose.
@Test @MainActor func aSmallVerticalFieldIsFortySixAtThreeLines() throws {
    #expect(try fieldHeight { vfield(lines(3)).lineLimit(1...8) }.rounded() == 56, "the regular control size is 56")
    let (window, _) = try open {
        Box { VStack(alignment: .leading, spacing: 0) {
            vfield(lines(3)).lineLimit(1...8).frame(width: Pixels(200)).fixedSize(horizontal: false, vertical: true)
        }.controlSize(.small) }
    }
    #expect(try fieldHit(window).bounds.size.height.value == 46, "small, 3 lines: 3 * 13 + 2 * 3.5 (SwiftUI: 50)")
}

/// **Divergence 240, finding K** (`SA-N` item 10; probe F): a flexible `.frame(minHeight: 16, maxHeight: 128)` under
/// `.fixedSize(horizontal: false, vertical: true)` hands its child no proposal, and `LayoutTree.placeNative`'s `.frame` case places
/// the child at its ideal, so a 20-line `TextEditor` is 320 tall here; SwiftUI clamps the child to the maximum (128, probe F) and
/// grows it 16 -> 96 -> 128. Pinned wrong on purpose; not fixed in this PR.
@Test @MainActor func aFlexibleFrameUnderFixedSizeDoesNotClampItsChildToTheMaximum() throws {
    func height(_ count: Int) throws -> Float {
        let (window, _) = try open {
            Box { VStack(alignment: .leading, spacing: 0) {
                TextEditor("", text: lines(count), onChange: { _ in }).frame(minHeight: Pixels(16), maxHeight: Pixels(128))
                    .fixedSize(horizontal: false, vertical: true).frame(width: Pixels(200))
            } }
        }
        return try fieldHit(window).bounds.size.height.value
    }
    #expect(try height(1) == 16, "the minimum holds")
    #expect(try height(20) == 320, "pinned wrong on purpose: SwiftUI answers 128 (finding K)")
}

// MARK: - 21 the API

/// **21** (`VT-C`): `.lineLimit` written on the field keeps it a `TextField`, so `.onSubmit` chains after it and it after `.onSubmit`.
/// This compiles only with the field's own overloads.
///
/// Mutation M21: the five own overloads deleted fails to compile (`lineLimit` returns an `EnvironmentScope`).
@Test @MainActor func lineLimitOnAFieldKeepsItAFieldAndChainsWithOnSubmit() {
    let a: TextField = TextField("x", text: .constant(""), axis: .vertical).onSubmit {}.lineLimit(1...8)
    let b: TextField = TextField("x", text: .constant(""), axis: .vertical).lineLimit(1...8).onSubmit {}
    #expect(a.ownLineLimit == TextLineLimit(min: 1, max: 8) && b.ownLineLimit == a.ownLineLimit && a.submit != nil && b.submit != nil)
    #expect(TextField("x", text: .constant(""), axis: .vertical).lineLimit(3, reservesSpace: true).ownLineLimit
            == TextLineLimit(min: 3, max: 3))
    #expect(TextField("x", text: .constant(""), axis: .vertical).lineLimit(5...).ownLineLimit == TextLineLimit(min: 5, max: nil))
    #expect(TextField("x", text: .constant(""), axis: .vertical).lineLimit(...5).ownLineLimit == TextLineLimit(min: nil, max: 5))
    #expect(TextField("x", text: .constant(""), axis: .vertical).lineLimit(nil).ownLineLimit == TextLineLimit(min: nil, max: nil))
    #expect(TextField("x", text: .constant("")).axis == .horizontal && TextField("x", text: .constant(""), axis: .vertical).isVertical)
}
