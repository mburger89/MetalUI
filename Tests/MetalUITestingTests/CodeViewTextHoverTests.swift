import Testing
import Foundation
import Observation
import MetalUI
import MetalUIScene
import MetalUITesting

// `CodeView.onTextHover` (`CV-AS`, record 283, Alloy G35 F): `.active` once after a rest on text, `.moved` at once on other
// text, `.ended` on every end, with a 150 ms grace while a text-anchored popover of the view is open. The delay and the
// grace are the timeline store's deadlines (one wake each), never the display link. PLAIN imports; the harness text
// system.

@Observable @MainActor private final class HoverModel {
    var phases: [CodeHoverPhase] = []
    var shown = false
    var shownBinding: Binding<Bool> { Binding(get: { self.shown }, set: { self.shown = $0 }) }
    var actives: Int { phases.filter { if case .active = $0 { true } else { false } }.count }
    var moves: [CodeHit] { phases.compactMap { if case .moved(let hit) = $0 { hit } else { nil } } }
    var ends: Int { phases.filter { $0 == .ended }.count }
}

/// Rows 0-2 are text, row 3 holds the word under test, the rest are empty lines (so a point there is past the line's end).
private let hoverText = (0..<3).map { "row\($0) alpha beta gamma\n" }.joined() + "   target word here\n" + String(repeating: "\n", count: 40)

@MainActor private struct HoverFixture {
    var window: TestWindow
    var buffer: CodeBuffer
    var geometry: CodeViewGeometry
    var model: HoverModel
    var scroll: CodeScrollState

    /// The centre of the first rectangle of `needle` on row 3.
    func word(_ needle: String) throws -> Point<Pixels> {
        let snap = buffer.snapshot()
        let line = snap.line(3)
        let r = try #require(line.range(of: needle))
        let start = snap.lineRange(3).lowerBound + line.utf8.distance(from: line.startIndex, to: r.lowerBound)
        let rect = try #require(geometry.rects(for: start..<(start + needle.utf8.count)).first)
        return pt(rect.origin.x.value + rect.size.width.value / 2, rect.origin.y.value + rect.size.height.value / 2)
    }

    /// A point on an empty row well below the word, inside the view and clear of the popover.
    func blank(row: Int = 20, x: Float = 300) throws -> Point<Pixels> {
        let rect = try #require(geometry.rects(for: buffer.snapshot().lineRange(3)).first)
        return pt(x, rect.origin.y.value + Float(row - 3) * rect.size.height.value + rect.size.height.value / 2)
    }
}

/// A 400 x 300 window with a 400 x 200 view whose hover reports into the model; `popover` adds the text-anchored popover on
/// "target" that opens on `.active` and closes on `.ended`, as Alloy's does.
@MainActor private func hoverFixture(delay: Duration = .milliseconds(300), handler: Bool = true,
                                     popover: Bool = false, readOnlyText: String? = nil) throws -> HoverFixture {
    let buffer = CodeBuffer(readOnlyText ?? hoverText)
    let model = HoverModel()
    let geometry = CodeViewGeometry()
    let scroll = CodeScrollState()
    let word: Range<Int> = {
        let snap = buffer.snapshot()
        let line = snap.line(3)
        let r = line.range(of: "target")!
        let start = snap.lineRange(3).lowerBound + line.utf8.distance(from: line.startIndex, to: r.lowerBound)
        return start..<(start + 6)
    }()
    let window = try harnessWindow(size: sz(400, 300)) {
        let base = CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).showsLineNumbers(false)
            .codeCaretBlink(.off).geometry(geometry).scrollState(scroll)
        return VStack(spacing: 0) {
            if popover {
                base.onTextHover(delay: delay) { phase in
                    model.phases.append(phase)
                    if case .active = phase { model.shown = true }
                    if phase == .ended { model.shown = false }
                }
                .popover(isPresented: model.shownBinding, attachmentAnchor: .range(word), arrowEdge: .bottom) { Text("POP") }
                .frame(width: Pixels(400), height: Pixels(200))
            } else if handler {
                base.onTextHover(delay: delay) { model.phases.append($0) }.frame(width: Pixels(400), height: Pixels(200))
            } else {
                base.frame(width: Pixels(400), height: Pixels(200))
            }
            Spacer(minLength: 0)
        }
    }
    window.tick(); window.tick(); window.tick()
    return HoverFixture(window: window, buffer: buffer, geometry: geometry, model: model, scroll: scroll)
}

/// Draws the frames a state write from a callback needs (an observed write dirties the window asynchronously off Apple).
@MainActor private func settle(_ window: TestWindow) {
    window.window.setNeedsRedraw()
    window.tick(); window.tick(); window.tick()
}

/// 1 — a rest fires `.active` once after the delay, from the one wake the deadline schedules: the frames in between are
/// none (no display link, no active animation), the callback runs after the frame, and nothing fires again.
/// **Mutation:** `noteActiveAnimation()` in place of the deadline (`hasActiveAnimations` is true and frames run every tick).
@Test @MainActor func aRestFiresActiveOnceAfterTheDelayFromOneWakeWithoutTheLink() throws {
    let f = try hoverFixture()
    let w = f.window
    w.hover(at: try f.word("target"))
    w.tick()
    #expect(f.model.phases.isEmpty, "nothing yet")
    #expect(!w.window.hasActiveAnimations, "the delay keeps no display link running")
    let frames = w.framesDrawn
    for _ in 0..<4 {   // 0.2 s in 50 ms ticks: before the delay
        w.advance(by: 0.05)
        #expect(!w.window.hasActiveAnimations)
    }
    #expect(f.model.phases.isEmpty && w.framesDrawn == frames, "no frame before the delay: \(w.framesDrawn - frames)")
    w.advance(by: 0.1)   // 0.3 s
    #expect(f.model.actives == 1, "\(f.model.phases)")
    guard case .active(let hit) = try #require(f.model.phases.first) else { Issue.record("not active"); return }
    #expect(hit.region == .text && hit.row == 3 && hit.character != nil)
    #expect(w.framesDrawn - frames == 1, "one frame, the wake's: \(w.framesDrawn - frames)")
    let after = w.framesDrawn
    for _ in 0..<10 { w.advance(by: 0.2) }
    #expect(f.model.phases.count == 1 && w.framesDrawn == after, "once, and quiet after: \(f.model.phases), \(w.framesDrawn - after) frames")
}

/// 2 — moving onto another grapheme before the delay restarts it (nothing reported), the same grapheme does not; once
/// active, a move onto other text is `.moved` at once, with that hit, and a move within the grapheme is silent.
/// **Mutation:** the pending phase not clearing `timerStart` on a new grapheme (`.active` fires 0.3 s after the first rest).
@Test @MainActor func movingRestartsTheDelayAndReportsMovedImmediately() throws {
    let f = try hoverFixture()
    let w = f.window
    let a = try f.word("target"), b = try f.word("word")
    w.hover(at: a)
    w.advance(by: 0.2)
    w.hover(at: b)           // restarts
    w.advance(by: 0.2)       // 0.4 s since the first rest, 0.2 since the move
    #expect(f.model.phases.isEmpty, "the delay restarted: \(f.model.phases)")
    w.hover(at: pt(b.x.value + 0.5, b.y.value))   // the same grapheme: no restart
    w.advance(by: 0.1)
    #expect(f.model.actives == 1, "300 ms after the move onto 'word': \(f.model.phases)")
    w.hover(at: a)           // other text: at once
    #expect(f.model.moves.count == 1 && f.model.phases.count == 2, "\(f.model.phases)")
    let moved = try #require(f.model.moves.first)
    #expect(moved == f.geometry.hit(at: a), "\(moved)")
    w.hover(at: pt(a.x.value + 0.5, a.y.value))
    #expect(f.model.moves.count == 1, "within the grapheme is silent")
    w.advance(by: 1)
    #expect(f.model.phases.count == 2, "and nothing fires by itself: \(f.model.phases)")
}

/// 3 — typed text, a key, a press and a wheel scroll each end an active hover (`.ended` once) and silently cancel a
/// pending one. **Mutation:** the `hardEnd()` removed from `insert`, `key`, `press` or the wheel closure reddens its row.
@Test @MainActor func typingAPressAndTheWheelEndTheHover() throws {
    for action in ["typed text", "a key", "a press", "the wheel", "an edit"] {
        let f = try hoverFixture()
        let w = f.window
        w.click(at: try f.blank())   // focus the view
        let target = try f.word("target")
        w.hover(at: target)
        w.advance(by: 0.3)
        #expect(f.model.actives == 1, "\(action): \(f.model.phases)")
        switch action {
        case "typed text": w.typeText("x")
        case "a key": w.typeKey(.rightArrow)
        case "a press": w.click(at: target)
        case "the wheel": w.scroll(at: target, byDeltaX: 0, deltaY: -3)
        default:
            f.buffer.replace(0..<0, with: "z")
            settle(w)
        }
        #expect(f.model.ends == 1 && f.model.phases.last == .ended, "\(action): \(f.model.phases)")
        w.advance(by: 1)
        #expect(f.model.ends == 1 && f.model.actives == 1, "\(action) stays ended: \(f.model.phases)")
        // Pending: cancelled with no callback.
        let g = try hoverFixture()
        g.window.click(at: try g.blank())
        g.window.hover(at: try g.word("target"))
        g.window.advance(by: 0.1)
        g.window.typeKey(.rightArrow)
        g.window.advance(by: 1)
        #expect(g.model.phases.isEmpty, "\(action): a pending hover ended by a key reports nothing: \(g.model.phases)")
    }
}

/// 4 — a view with no handler adds no state write as the pointer moves over it and time passes: its four moves write what
/// the view wrote before the hover existed (two plain writes a move, the scroll chrome's, 8 in all), and a view with a
/// handler writes more as the grapheme changes, which the same count sees.
/// **Mutation:** the hover attachment installed unconditionally (a handler-less view's moves write the hover track).
@Test @MainActor func noHoverHandlerNoStateWrites() throws {
    func plainWrites(_ f: HoverFixture) throws -> (writes: Int, phases: Int) {
        let w = f.window
        w.hover(at: pt(5, 5))
        w.advance(by: 0.1)
        let before = w.window.testingStatePlainWriteCount
        for point in [try f.word("word"), try f.word("here"), try f.blank(), try f.word("target")] {
            w.hover(at: point)
            w.advance(by: 0.6)
        }
        return (w.window.testingStatePlainWriteCount - before, f.model.phases.count)
    }
    let none = try plainWrites(try hoverFixture(handler: false))
    #expect(none.writes == 8 && none.phases == 0, "nothing added without a handler: \(none)")
    let with = try plainWrites(try hoverFixture())
    #expect(with.writes > none.writes && with.phases > 0, "and a handler's moves do write: \(with)")
}

/// A host the retained replay can replay: an `.equatable()` component over the view and its text-anchored popover.
@MainActor private struct HoverHost: Component, @MainActor Equatable {
    let buffer: CodeBuffer, geometry: CodeViewGeometry, model: HoverModel, word: Range<Int>
    static func == (a: HoverHost, b: HoverHost) -> Bool { a.buffer === b.buffer && a.model === b.model }
    var content: some ElementGroup {
        CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).showsLineNumbers(false)
            .codeCaretBlink(.off).geometry(geometry)
            .onTextHover(delay: .milliseconds(300)) { phase in
                model.phases.append(phase)
                if case .active = phase { model.shown = true }
                if phase == .ended { model.shown = false }
            }
            .popover(isPresented: model.shownBinding, attachmentAnchor: .range(word), arrowEdge: .bottom) { Text("POP") }
            .frame(width: Pixels(400), height: Pixels(200))
    }
}

/// 5 — a hover that waits on a deadline survives frames forced by something else, in an `.equatable()` host that retained
/// replay would otherwise replay: with the pointer off the view the host holds an open presentation (ineligible,
/// `presentation` and `portal`) and a hovered view is never replayed, so the deadline is never dropped, and under
/// `METALUI_VERIFY_RETAINED=1` the frames are compared with rebuilt ones. **The `taintRetention` is defensive, not pinned
/// here:** removing it does not redden this test, because both of its cases are already ineligible (recorded in `CV-AS`).
@Test @MainActor func retainedVerifyStaysGreenWithAPendingHover() throws {
    let buffer = CodeBuffer(hoverText)
    let model = HoverModel()
    let geometry = CodeViewGeometry()
    let snap = buffer.snapshot()
    let start = snap.lineRange(3).lowerBound + snap.line(3).utf8.distance(from: snap.line(3).startIndex, to: snap.line(3).range(of: "target")!.lowerBound)
    let window = try harnessWindow(size: sz(400, 300)) {
        VStack(spacing: 0) {
            HoverHost(buffer: buffer, geometry: geometry, model: model, word: start..<(start + 6)).equatable()
            Spacer(minLength: 0)
        }
    }
    window.tick(); window.tick(); window.tick()
    let f = HoverFixture(window: window, buffer: buffer, geometry: geometry, model: model, scroll: CodeScrollState())
    window.hover(at: try f.word("target"))
    window.advance(by: 0.3)
    settle(window)
    #expect(model.actives == 1 && model.shown, "\(model.phases)")
    window.hover(at: pt(200, 280))   // off the view: the host may replay now
    for _ in 0..<3 {
        window.advance(by: 0.03)
        settle(window)
    }
    #expect(model.ends == 0, "inside the grace: \(model.phases)")
    window.advance(by: 0.1)
    #expect(model.ends == 1 && !model.shown, "the grace's deadline survived the replayed frames: \(model.phases)")
}

/// 6 — the pointer leaving the text for the open popover within the grace keeps the hover: no `.ended` while it is inside,
/// however long, and `.ended` comes the grace after it leaves the popover. **Mutation:** `panel(_:)` ignored (`.ended`
/// fires 150 ms after the pointer left the text).
@Test @MainActor func leavingIntoTheOpenPopoverWithinTheGraceKeepsTheHover() throws {
    let f = try hoverFixture(popover: true)
    let w = f.window
    w.hover(at: try f.word("target"))
    w.advance(by: 0.3)
    settle(w)
    #expect(f.model.actives == 1 && f.model.shown)
    let panel = try w.element(label: "POP").frame
    let inside = pt(panel.origin.x.value + panel.size.width.value / 2, panel.origin.y.value + panel.size.height.value / 2)
    w.hover(at: try f.blank(row: 6, x: panel.origin.x.value + panel.size.width.value / 2))   // the gap: left the text
    w.advance(by: 0.05)
    w.hover(at: inside)   // inside the panel within the grace
    for _ in 0..<6 { w.advance(by: 0.3) }
    #expect(f.model.ends == 0 && f.model.shown, "held while inside, 1.8 s: \(f.model.phases)")
    w.hover(at: try f.blank(row: 25))   // out of the popover, onto nothing
    w.advance(by: 0.1)
    #expect(f.model.ends == 0, "inside the grace: \(f.model.phases)")
    w.advance(by: 0.1)
    #expect(f.model.ends == 1 && !f.model.shown, "ended after the grace: \(f.model.phases)")
}

/// 7 — with no text-anchored presentation open, leaving the text ends the hover in the same input.
/// **Mutation:** the grace applied without checking the box (`.ended` waits 150 ms).
@Test @MainActor func leavingWithNoPopoverEndsImmediately() throws {
    let f = try hoverFixture()
    let w = f.window
    w.hover(at: try f.word("target"))
    w.advance(by: 0.3)
    w.hover(at: try f.blank())
    #expect(f.model.ends == 1, "\(f.model.phases)")
    // Leaving the view altogether too.
    w.hover(at: try f.word("word"))
    w.advance(by: 0.3)
    #expect(f.model.actives == 2)
    w.exitPointer()
    #expect(f.model.ends == 2, "\(f.model.phases)")
}

/// 8 — the grace expires outside both: the pointer leaves the text for nothing and `.ended` comes at 150 ms from one wake;
/// back on the text within it is `.moved` or silence, and a press ends at once. **Mutation:** the grace deadline not noted
/// (`.ended` waits for the next input).
@Test @MainActor func graceExpiresOutsideBothEnds() throws {
    let f = try hoverFixture(popover: true)
    let w = f.window
    let target = try f.word("target")
    w.hover(at: target)
    w.advance(by: 0.3)
    settle(w)
    #expect(f.model.actives == 1 && f.model.shown)
    w.hover(at: try f.blank())
    #expect(f.model.ends == 0 && !w.window.hasActiveAnimations)
    let frames = w.framesDrawn
    w.advance(by: 0.1)
    #expect(f.model.ends == 0)
    w.advance(by: 0.06)
    #expect(f.model.ends == 1 && !f.model.shown, "\(f.model.phases)")
    #expect(w.framesDrawn - frames <= 2, "from the wake: \(w.framesDrawn - frames)")
    // Back on text within the grace: nothing ends; another grapheme is `.moved`.
    settle(w)
    w.hover(at: target)
    w.advance(by: 0.3)
    settle(w)
    #expect(f.model.actives == 2 && f.model.shown)
    w.hover(at: try f.blank())
    w.advance(by: 0.1)
    w.hover(at: target)
    w.advance(by: 1)
    #expect(f.model.ends == 1 && f.model.moves.isEmpty, "returning to the same grapheme changes nothing: \(f.model.phases)")
    w.hover(at: try f.blank())
    w.advance(by: 0.1)
    w.hover(at: try f.word("here"))
    #expect(f.model.moves.count == 1 && f.model.ends == 1, "returning to other text is moved: \(f.model.phases)")
    w.advance(by: 1)
    #expect(f.model.ends == 1)
    // Escape ends it at once, whatever the grace (the popover takes the key and dismisses).
    w.hover(at: try f.blank())
    w.typeKey(.escape)
    settle(w)
    #expect(f.model.ends == 2, "\(f.model.phases)")
}
