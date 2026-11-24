import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing
@testable import MetalUI

// `textSelection(_:)` on `Text` (rulings `TXS-A`…`TXS-H`, decisions `docs/superpowers/2026-11-23-text-selectability-decisions.md`,
// record 399). The harness drives real pointer events and the real ⌘C / ⌘A keystroke. Probe
// `docs/probes/swiftui-text-selection-enabled.swift`. PLAIN harness text (Noto Sans), `Modifiers.primary` (⌘ on Apple, Ctrl
// elsewhere), `runUntilIdle()` then `tick()` and summed `frameWork`, so Linux and Windows run every arm that is not
// Darwin-only (the allocation counter). Builders are kept narrow (PE-K: Windows' 1 MB debug test thread).

// MARK: Fixtures

private let alpha = "alpha beta gamma delta"

@MainActor private final class TextModel {
    var text = ""
    var show = false
}

/// One selectable `Text` in a column.
@MainActor private func oneText(_ string: String = alpha, width: Pixels? = nil, size: Size<Pixels> = sz(400, 300)) throws -> TestWindow {
    try harnessWindow(size: size) {
        Column {
            if let width { Text(string).textSelection(.enabled).frame(width: width) } else { Text(string).textSelection(.enabled) }
        }
    }
}

/// The two selectable `Text`s of the tests that need a second.
@MainActor private func twoTexts(_ first: String = "first text A", _ second: String = "second text B") throws -> TestWindow {
    try harnessWindow(size: sz(400, 300)) {
        Column {
            Text(first).textSelection(.enabled)
            Text(second).textSelection(.enabled)
        }
    }
}

/// The window rect of the `index`-th selectable `Text` the last frame registered.
@MainActor private func box(_ w: TestWindow, _ index: Int = 0) -> Bounds<Pixels> {
    let region = w.window.lastSelectableRegions[index]
    return w.window.lastHitboxes[region.hitbox].bounds
}

/// A point `dx` right of and `dy` below the `index`-th `Text`'s top-leading corner.
@MainActor private func at(_ w: TestWindow, _ dx: Float, _ dy: Float = 8, index: Int = 0) -> Point<Pixels> {
    let b = box(w, index)
    return pt(b.origin.x.value + dx, b.origin.y.value + dy)
}

/// The window point at the middle of grapheme boundary `boundary` on line `line` of the selected `Text` (its geometry is
/// built by the first press).
@MainActor private func boundaryPoint(_ w: TestWindow, _ boundary: Int, line: Int = 0, index: Int = 0) throws -> Point<Pixels> {
    let geometry = try #require(w.window.textSelectionSession?.geometry, "a press built the geometry")
    let l = geometry.lines[line]
    let x = l.originX + l.offsets[boundary - l.range.lowerBound]
    return at(w, Float(x), Float(l.top + l.height / 2), index: index)
}

@MainActor private func selected(_ w: TestWindow) -> String? { w.window.textSelectionSession?.selectedText }

/// A press on the `index`-th `Text`'s start that builds the session and its geometry.
@MainActor private func press(_ w: TestWindow, _ index: Int = 0) async throws {
    w.click(at: at(w, 1, index: index))
    try await w.runUntilIdle()
    w.tick()
}

/// The accent-tinted fills (a selection's highlight) the last frame drew.
@MainActor private func highlightFills(_ w: TestWindow) -> Int {
    w.allRects.filter { $0.background.a > 0.2 && $0.background.a < 0.4 && $0.bounds.size.width > 4 }.count
}

// MARK: 2 — the API and the environment

/// **2.1** `textSelection(_:)` takes `.enabled` and `.disabled` and the value spells as SwiftUI's; a custom conformer works;
/// the flag is inherited through containers and the nearest writer wins (probe `E0`, `E1`, `E1b`).
/// **Mutation:** write `true` whatever `allowsSelection` says (`.disabled` then selects).
@Test @MainActor func textSelectionIsInheritedAndTheNearestWriterWins() async throws {
    struct Always: TextSelectability { static var allowsSelection: Bool { true } }
    let w = try harnessWindow(size: sz(400, 300)) {
        Column {
            Column {
                Text("outer one").frame(width: 120)
                Text("inner off").textSelection(.disabled).frame(width: 120)
                Text("custom").frame(width: 120)
            }
            .textSelection(.enabled)
            Text("none").frame(width: 120)
            Column { Text("inner on").textSelection(Always()).frame(width: 120) }.textSelection(.disabled)
        }
    }
    try await w.runUntilIdle()
    let strings = w.window.lastSelectableRegions.map(\.string)
    #expect(strings == ["outer one", "custom", "inner on"], "\(strings)")
    #expect(EnabledTextSelectability.allowsSelection && !DisabledTextSelectability.allowsSelection)
}

// MARK: 2b — the retained fingerprint

/// **2.2** Two environments differing only in the selection flag have different retained fingerprints (a retained occurrence
/// is replayed only under an equal one), and the difference is named `textSelectionEnabled`.
/// **Mutation:** `retainedFingerprint` carries `false` for the flag.
@Test @MainActor func theRetainedFingerprintCarriesTheSelectionFlag() {
    let off = EnvironmentValues()
    var on = off
    on.textSelectionEnabled = true
    #expect(off.retainedFingerprint != on.retainedFingerprint)
    #expect(on.retainedFingerprint.differences(from: off.retainedFingerprint) == ["textSelectionEnabled"])
}

// MARK: 3 — the geometry

/// **3.1** A press at a point lands on the nearest grapheme boundary of its line, above the text is the start and below it
/// the end; the boundaries of a wrapped text span its lines, hard breaks excluded.
/// **Mutation:** `boundary(at:)` ignores `y` (every press lands on line 0).
@Test @MainActor func aPressLandsOnTheNearestBoundaryOfTheLineUnderIt() async throws {
    let w = try oneText("one two three four five six seven", width: 70)
    try await press(w)
    let geometry = try #require(w.window.textSelectionSession?.geometry)
    #expect(geometry.lines.count > 2, "it wrapped: \(geometry.lines.map(\.range))")
    for (n, line) in geometry.lines.enumerated() where line.range.count > 1 {
        let middle = line.range.lowerBound + 1
        let point = pt(Float(line.originX + line.offsets[1]) + 0.25, Float(line.top + line.height / 2))
        #expect(geometry.boundary(at: point) == middle, "line \(n): \(geometry.boundary(at: point)) vs \(middle)")
    }
    #expect(geometry.boundary(at: pt(5, -20)) == 0, "above the text is its start")
    #expect(geometry.boundary(at: pt(5, 5_000)) == geometry.graphemeCount, "below it is its end")
    #expect(geometry.lines.first!.range.lowerBound == 0 && geometry.lines.last!.range.upperBound <= geometry.graphemeCount)
}

/// **3.2** A trailing-aligned text's shorter line starts where the text system put it (`originX`): a press at that line's
/// right edge finds its last boundary, one left of its first glyph finds its first, and the highlight rect starts at the
/// aligned x.
/// **Mutation:** drop `originX` from `boundary(at:)` and `rects(for:)`.
@Test @MainActor func anAlignedLineKeepsItsOffset() async throws {
    let w = try harnessWindow(size: sz(400, 300)) {
        Column { Text("one two three").multilineTextAlignment(.trailing).textSelection(.enabled).frame(width: 60) }
    }
    try await w.runUntilIdle()
    try await press(w)
    let geometry = try #require(w.window.textSelectionSession?.geometry)
    try #require(geometry.lines.count >= 2)
    let shortLine = try #require(geometry.lines.first { $0.originX > 1 }, "a line is aligned right of the box's left: \(geometry.lines.map(\.originX))")
    let mid = Float(shortLine.top + shortLine.height / 2)
    #expect(geometry.boundary(at: pt(Float(shortLine.originX) - 0.5, mid)) == shortLine.range.lowerBound)
    #expect(geometry.boundary(at: pt(Float(shortLine.originX + shortLine.offsets.last!) + 20, mid)) == shortLine.range.upperBound)
    let rects = geometry.rects(for: shortLine.range)
    #expect(rects.count == 1 && abs(Double(rects[0].origin.x.value) - shortLine.originX) < 0.01, "\(rects)")
}

/// **3.3** Styled runs: a larger run's boundaries come from its own font (per-run `caretOffsets`), and the offsets are monotonic
/// across the run boundaries.
/// **Mutation:** measure every run in the first run's font (the larger run's offsets shrink to the first's).
@Test @MainActor func aStyledTextMeasuresEachRunInItsOwnFace() async throws {
    let w = try harnessWindow(size: sz(400, 300)) {
        Column { (Text("MMMM ") + Text("MMMM").font(size: 26) + Text(" MMMM")).textSelection(.enabled) }
    }
    try await w.runUntilIdle()
    try await press(w)
    let geometry = try #require(w.window.textSelectionSession?.geometry)
    let offsets = geometry.lines[0].offsets
    #expect(offsets.count == 15 && zip(offsets, offsets.dropFirst()).allSatisfy { $0 <= $1 }, "\(offsets)")
    let first = offsets[4] - offsets[0], large = offsets[9] - offsets[5], last = offsets[14] - offsets[10]
    #expect(large > first * 1.7, "four capitals at 26 pt are wider than four at the default size: \(large) vs \(first)")
    #expect(abs(last - first) < 1, "the same four capitals either side: \(last) vs \(first)")
}

/// A log of about `kib` KiB.
private func logOf(kib: Int) -> String {
    let line = "2026-11-23 12:00:00 plugin stderr: something happened here and then again\n"
    return String(repeating: line, count: kib * 1024 / line.utf8.count)
}

/// A text system that counts what the geometry asks it to measure per grapheme (`caretOffsets`), over the real portable one.
@MainActor private final class SelectionCountingTextSystem: TextSystem {
    let base: any TextSystem
    var caretCalls = 0
    var caretUnits = 0
    init(_ base: any TextSystem) { self.base = base }
    func resolveFont(_ descriptor: FontDescriptor) -> FontKey { base.resolveFont(descriptor) }
    func fontMetrics(_ font: FontKey) -> TextFontMetrics { base.fontMetrics(font) }
    func measure(_ string: String, font: FontKey, wrappingAt width: Double?, options: TextLayoutOptions) -> TextMeasurement {
        base.measure(string, font: font, wrappingAt: width, options: options)
    }
    func placeGlyphs(_ string: String, font: FontKey, wrappingAt width: Double?, options: TextLayoutOptions,
                     origin: (x: Double, y: Double), scaleFactor: Float) -> [TextGlyph] {
        base.placeGlyphs(string, font: font, wrappingAt: width, options: options, origin: origin, scaleFactor: scaleFactor)
    }
    func caretOffsets(_ string: String, font: FontKey) -> [Double] {
        caretCalls += 1
        caretUnits += string.count
        return base.caretOffsets(string, font: font)
    }
    func lineRanges(_ string: String, font: FontKey, wrappingAt width: Double?, options: TextLayoutOptions) -> [Range<Int>] {
        base.lineRanges(string, font: font, wrappingAt: width, options: options)
    }
    func measure(_ text: StyledText, wrappingAt width: Double?, options: TextLayoutOptions) -> StyledTextMeasurement {
        base.measure(text, wrappingAt: width, options: options)
    }
    func layOut(_ text: StyledText, wrappingAt width: Double?, options: TextLayoutOptions,
                origin: (x: Double, y: Double), scaleFactor: Float) -> StyledTextLayout {
        base.layOut(text, wrappingAt: width, options: options, origin: origin, scaleFactor: scaleFactor)
    }
    func decorationMetrics(_ font: FontKey) -> TextDecorationMetrics { base.decorationMetrics(font) }
    func rasterize(_ key: GlyphKey) -> GlyphImage { base.rasterize(key) }
    func beginFrame() { base.beginFrame() }
    func endFrame() { base.endFrame() }
}

/// The geometry of `log` at 380 pt, and what it asked the text system to measure.
@MainActor private func countedGeometry(_ log: String) -> (geometry: SelectableTextGeometry, calls: Int, units: Int) {
    let system = SelectionCountingTextSystem(harnessTextSystem())
    let resolved = resolveRichText(.plain(log), own: TextStyleRequest(), rich: TextRichFields(), in: EnvironmentValues(), system: system)
    let geometry = SelectableTextGeometry.make(resolved, index: SelectableTextIndex(log), wrappingAt: 380, height: .infinity, system: system)
    return (geometry, system.caretCalls, system.caretUnits)
}

/// **3.4** The geometry of a log covers every line and grapheme of the string and measures each grapheme once: one `caretOffsets`
/// call per line, over that line's graphemes, so the units measured are the graphemes less the hard breaks, at 4 KiB and at
/// 16 KiB alike (a build that measures the whole string per line, or the text again per run, makes the units grow with the lines
/// times the log). Counted work, not a clock: a 64 KiB log is the same arithmetic (measured once, record 399).
/// **Mutation:** `offsets(of:)` measures `index.string(0..<index.count)` for each line.
@Test @MainActor func aLogsGeometryCoversItAndMeasuresEachGraphemeOnce() throws {
    let small = logOf(kib: 4), large = logOf(kib: 16)
    let a = countedGeometry(small), b = countedGeometry(large)
    for (log, result) in [(small, a), (large, b)] {
        let breaks = log.filter(\.isNewline).count
        #expect(result.geometry.graphemeCount == log.count)
        #expect(result.calls == result.geometry.lines.count, "one call per line: \(result.calls) of \(result.geometry.lines.count)")
        #expect(result.units == log.count - breaks, "every grapheme once, no hard break: \(result.units) of \(log.count - breaks)")
        #expect(result.geometry.lines.last!.range.upperBound >= log.count - 1, "the lines reach the end")
    }
    #expect(b.geometry.lines.count > a.geometry.lines.count * 3 && b.units > a.units * 3)
}

/// **3.5** A drag across a tall log does not build the geometry again: the press builds it once, a drag only moves the head.
/// **Mutation:** clear `session.geometry` in `enqueue` (the build count reaches the drag's steps).
@Test @MainActor func aDragBuildsNoSecondGeometry() async throws {
    let w = try oneText(logOf(kib: 2), width: 380, size: sz(400, 4_000))
    try await press(w)
    let before = try #require(w.window.textSelectionSession?.geometry)
    w.drag(from: at(w, 1), to: at(w, 200, 300), steps: 4)
    try await w.runUntilIdle()
    let after = try #require(w.window.textSelectionSession?.geometry)
    #expect(after.lines.count == before.lines.count && after.width == before.width)
    #expect(w.window.textSelectionSession?.geometryBuilds == 1, "built once for the press, never for the drag: \(String(describing: w.window.textSelectionSession?.geometryBuilds))")
    #expect((selected(w) ?? "").count > 100, "the drag selected a run: \((selected(w) ?? "").count)")
}

// MARK: 4 — registration and cost (TXS-H)

/// A row with no modifier.
private struct PlainRow: Component {
    let index: Int
    var content: some ElementGroup { Text(verbatim: "row \(index) of the log").frame(width: 160) }
}

/// A row with the modifier, enabled or disabled: two arms of one `if`, so the two twins build the same identities (a three-way
/// `switch` nests its arms one level deeper each, an identity and an array per row that is the fixture's, not the feature's).
private struct GateRow: Component {
    let index: Int
    let on: Bool
    var content: some ElementGroup {
        if on { Text(verbatim: "row \(index) of the log").textSelection(.enabled).frame(width: 160) }
        else { Text(verbatim: "row \(index) of the log").textSelection(.disabled).frame(width: 160) }
    }
}

/// A cost window opens with **no accessibility client**: the harness's default is one, and its tree work is not what these arms
/// price (`TXS-H`: accessibility work happens only while a client collects, pinned apart by 7.1).
@MainActor private func costWindow(rows: Int, selectable: Bool?, client: Bool = false) throws -> TestWindow {
    try harnessWindow(size: sz(400, 4_000), options: .init(accessibilityClientActive: client)) {
        Column {
            if let selectable {
                ForEach(0..<rows, id: \.self) { GateRow(index: $0, on: selectable) }
            } else {
                ForEach(0..<rows, id: \.self) { PlainRow(index: $0) }
            }
        }
    }
}

/// One steady frame's summed work and hitbox count.
@MainActor private func steadyFrame(_ w: TestWindow) async throws -> (work: FrameWork, hitboxes: Int, regions: Int) {
    try await w.runUntilIdle()
    for _ in 0..<2 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    w.resetFrameWork()
    w.window.setNeedsRedraw()
    try await w.runUntilIdle()
    return (totalWork(w), w.window.lastHitboxes.count, w.window.lastSelectableRegions.count)
}

/// **4.1** A tree with no `textSelection` registers no hitbox, no region and no session, and a `Text` costs what it did: a
/// steady frame of 20 rows is the literals master measured (see the record), and a flag-false twin equals it counter for
/// counter except for the modifier's own layer.
/// **Mutation:** register the hitbox whatever the flag says (drop `selectableBox`'s gate in `Text.prepaint`).
@Test @MainActor func aTextWithoutTextSelectionCostsWhatItCost() async throws {
    let plain = try await steadyFrame(try costWindow(rows: 20, selectable: nil))
    #expect(plain.hitboxes == 0 && plain.regions == 0, "no hitbox, no region: \(plain.hitboxes) \(plain.regions)")
    // The literals are the frame master draws for the same tree (measured at base 595c474a, record 399): 20 rows of two group
    // members each, 41 prepaints, 60 paints, one build, no layout work in a steady frame.
    #expect(plain.work.elementRequests == 40 && plain.work.elementPrepaints == 41 && plain.work.elementPaints == 60
            && plain.work.builds == 1 && plain.work.layoutMeasureCalls == 0,
            "\(plain.work.elementRequests) \(plain.work.elementPrepaints) \(plain.work.elementPaints) \(plain.work.builds)")
    let off = try await steadyFrame(try costWindow(rows: 20, selectable: false))
    #expect(off.hitboxes == 0 && off.regions == 0, "a disabled flag registers nothing")
    var normalised = off.work
    normalised.elementRequests = plain.work.elementRequests
    normalised.elementPrepaints = plain.work.elementPrepaints
    normalised.elementPaints = plain.work.elementPaints
    #expect(normalised == plain.work, "every other counter of a disabled twin equals the plain tree's")
}

/// **4.2** An enabled idle `Text` adds one hitbox and one region over the disabled twin and nothing else: every
/// `FrameWork` counter equals the twin's (the modifier's layer is in both), the hitbox count grows by exactly the row count,
/// at 10 rows and at 100.
/// **Mutation:** register a second hitbox per `Text` (the count doubles), or read `environmentSnapshot()` in the branch.
@Test @MainActor func anEnabledIdleTextCostsOneHitboxAndTheModifierLayer() async throws {
    for rows in [10, 100] {
        let off = try await steadyFrame(try costWindow(rows: rows, selectable: false))
        let on = try await steadyFrame(try costWindow(rows: rows, selectable: true))
        #expect(on.hitboxes == off.hitboxes + rows, "\(rows) rows: \(on.hitboxes) vs \(off.hitboxes)")
        #expect(on.regions == rows && off.regions == 0)
        #expect(on.work == off.work, "\(rows) rows: an enabled idle frame does a disabled twin's work")
    }
}

#if canImport(Darwin)
import MetalUITestSupport

/// One steady frame's heap allocations (a warm redraw, `malloc_logger`).
@MainActor private func allocations(rows: Int, selectable: Bool?) async throws -> Int {
    let w = try costWindow(rows: rows, selectable: selectable)
    try await w.runUntilIdle()
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick() }
    return try #require(countAllocations { w.window.setNeedsRedraw(); w.tick() })
}

/// **4.3** The allocations of an enabled idle frame do not grow with the row count over a disabled twin: the difference at
/// 10 rows and at 100 rows is the same within a handful (no closure, class box or id per `Text`; the region and hitbox
/// arrays are reserved from the last frame).
/// **Mutation:** a derived id (`GlobalElementID.child`) per selectable `Text` (+1 per row) or a closure in the region.
@Test @MainActor func anEnabledIdleTextAllocatesNothingPerRow() async throws {
    var delta: [Int: Int] = [:]
    for rows in [10, 100] {
        let off = try await allocations(rows: rows, selectable: false)
        let on = try await allocations(rows: rows, selectable: true)
        delta[rows] = on - off
    }
    #expect(abs(delta[100]! - delta[10]!) <= 2, "the enabled-minus-disabled allocations at 10 and at 100 rows: \(delta)")
    #expect(delta[100]! <= 8, "a constant, not a function of the rows: \(delta)")
}
#endif

/// **4.4** `.disabled(true)`, `.allowsHitTesting(false)` and `.hidden()` register no region (probe `E1c`, `E1d`: not
/// measured for a pointer, `HC-TXS-7`).
/// **Mutation:** drop the `registersPointerHitboxes` gate.
@Test @MainActor func aSelectableTextBehindAGateRegistersNoRegion() async throws {
    let w = try harnessWindow(size: sz(400, 300)) {
        Column {
            Text("live").textSelection(.enabled)
            Text("disabled").textSelection(.enabled).disabled(true)
            Text("no hits").textSelection(.enabled).allowsHitTesting(false)
            Text("hidden").textSelection(.enabled).hidden()
        }
    }
    try await w.runUntilIdle()
    #expect(w.window.lastSelectableRegions.map(\.string) == ["live"], "\(w.window.lastSelectableRegions.map(\.string))")
}

// MARK: 5 — the window stage

/// **5.1** A drag selects what it covers and the real ⌘C writes exactly that (probe `D1p`).
/// **Mutation:** `copyTextSelection` writes the whole string.
@Test @MainActor func dragSelectsAndPrimaryCCopies() async throws {
    let w = try oneText()
    try await press(w)
    w.drag(from: try boundaryPoint(w, 0), to: try boundaryPoint(w, 9))
    try await w.runUntilIdle()
    #expect(selected(w) == "alpha bet", "\(String(describing: selected(w)))")
    w.platformWindow.clipboard = nil
    w.typeKey("c", modifierFlags: .primary)
    #expect(w.platformWindow.clipboard == "alpha bet")
}

/// **5.2** A double click selects the word under it, a triple click the visual line it is on (not the whole text: the text
/// here wraps) and a fourth click its paragraph (provisional: `HC-TXS-2`).
/// **Mutation:** `TextEditing.press` called with `clickCount: 1`; a triple click taken as a double or as select-all.
@Test @MainActor func doubleClickSelectsAWord() async throws {
    let text = "one two three four five\nsix seven eight nine ten eleven"
    let w = try oneText(text, width: 90)
    try await press(w)
    let geometry = try #require(w.window.textSelectionSession?.geometry)
    try #require(geometry.lines.count >= 4, "\(geometry.lines.map(\.range))")
    let second = geometry.lines[1]
    let inside = try boundaryPoint(w, second.range.lowerBound + 1, line: 1)
    w.doubleClick(at: inside)
    try await w.runUntilIdle()
    let word = try #require(selected(w))
    #expect(!word.contains(" ") && !word.isEmpty && second.range.count > word.count, "a word of line 1: '\(word)'")
    let event = MouseEvent(position: inside, modifiers: [], clickCount: 3, buttonNumber: 0, timestamp: w.now)
    w.send(.mouseDown(event)); w.send(.mouseUp(event)); w.tick()
    let characters = Array(text)
    #expect(selected(w) == String(characters[second.range]), "a triple click selects its visual line: '\(String(describing: selected(w)))'")
    let fourth = MouseEvent(position: inside, modifiers: [], clickCount: 4, buttonNumber: 0, timestamp: w.now)
    w.send(.mouseDown(fourth)); w.send(.mouseUp(fourth)); w.tick()
    #expect(selected(w) == "one two three four five", "a fourth click its paragraph: '\(String(describing: selected(w)))'")
}

/// **5.3** ⌘A selects the whole of the one `Text` that has the session and nothing else; with no session it does nothing
/// and is declined (probe `A1`, `A1b`, `A1c`).
/// **Mutation:** `selectAll` over every region's strings joined.
@Test @MainActor func selectAllSelectsOnlyThatText() async throws {
    let w = try twoTexts()
    let noSession = w.send(.keyDown(KeyEvent(charactersIgnoringModifiers: "a", characters: "a", modifiers: .primary, timestamp: 0)))
    #expect(noSession == false, "no session: declined")
    try await press(w, 1)
    w.typeKey("a", modifierFlags: .primary)
    #expect(selected(w) == "second text B")
    w.typeKey("c", modifierFlags: .primary)
    #expect(w.platformWindow.clipboard == "second text B")
    #expect(w.window.textSelectionSession?.id == w.window.lastSelectableRegions[1].id)
    // Pressing the other `Text` replaces the session (probe `C3`), and ⌘A there takes that one.
    try await press(w, 0)
    #expect(w.window.textSelectionSession?.id == w.window.lastSelectableRegions[0].id)
    w.typeKey("a", modifierFlags: .primary)
    #expect(selected(w) == "first text A")
}

/// **5.4** The selection ends when focus moves to an element (a field, probe `C2`), and when its `Text` leaves the tree;
/// ⌘C then copies nothing.
/// **Mutation:** drop the `focusedElement` observer's `dropTextSelection()`, or `settleTextSelection`.
@Test @MainActor func focusLeavingTheTextDropsTheSelection() async throws {
    let model = TextModel()
    let w = try harnessWindow(size: sz(400, 300)) {
        Column {
            Text(alpha).textSelection(.enabled)
            TextField("field", text: Binding(get: { model.text }, set: { model.text = $0 })).frame(width: 150)
            if model.show { Text("second").textSelection(.enabled) }
        }
    }
    try await w.runUntilIdle()
    w.clearTheFirstDrawSeat()
    try await press(w)
    w.typeKey("a", modifierFlags: .primary)
    #expect(selected(w) == alpha)
    let field = try #require(w.window.lastHitboxes.first { $0.handlers.textInput != nil })
    w.click(at: pt(field.bounds.origin.x.value + 5, field.bounds.origin.y.value + 5))
    try await w.runUntilIdle()
    #expect(w.window.textSelectionSession == nil, "focus moved to a field")
    w.platformWindow.clipboard = nil
    w.typeKey("c", modifierFlags: .primary)
    #expect(w.platformWindow.clipboard == nil, "nothing is copied: the field has no selection")
    model.show = true
    w.window.setNeedsRedraw(); try await w.runUntilIdle()
    try await press(w, 1)
    #expect(w.window.textSelectionSession != nil)
    model.show = false
    w.window.setNeedsRedraw(); try await w.runUntilIdle()
    #expect(w.window.textSelectionSession == nil, "its Text left the tree")
}

/// The highlight rects of the selected `Text`'s first line in the last frame: fills as tall as the line and as wide as the whole
/// line's text (device pixels equal points in the harness).
@MainActor private func firstLineHighlights(_ w: TestWindow) throws -> [MUIRect] {
    let geometry = try #require(w.window.textSelectionSession?.geometry)
    let line = geometry.lines[0]
    let width = Float(line.offsets.last!)
    return w.allRects.filter { abs($0.bounds.size.height - Float(line.height)) < 0.5 && abs($0.bounds.size.width - width) < 1 }
}

/// **5.5** A press on empty space keeps the selection (probe `C1`), and so does the window losing key (`C5b`): the highlight stays,
/// in another colour (`HC-TXS-6`: the inactive one is MetalUI's choice).
/// **Mutation:** a press that is not on a region drops the session; the inactive colour equal to the key one.
@Test @MainActor func aPressOnEmptySpaceKeepsTheSelection() async throws {
    let w = try oneText()
    try await press(w)
    w.typeKey("a", modifierFlags: .primary)
    try await w.runUntilIdle()
    let key = try #require(try firstLineHighlights(w).first, "the whole line is highlighted")
    w.click(at: pt(5, 290))
    try await w.runUntilIdle()
    #expect(selected(w) == alpha, "a click on empty space")
    w.setControlActiveState(.inactive)
    try await w.runUntilIdle()
    #expect(selected(w) == alpha, "the window lost key")
    let inactive = try #require(try firstLineHighlights(w).first, "still highlighted")
    #expect(String(describing: inactive.background) != String(describing: key.background), "in the inactive colour")
}

/// **5.6** A press on a selectable `Text` blurs a focused field, and ⌘C then copies the `Text`'s selection, not the field's
/// (probe `F1p`/`F1q`; provisional until `HC-TXS-1`).
/// **Mutation:** drop the `focus(nil)` in the press stage (the field keeps ⌘C).
@Test @MainActor func aPressOnTheTextBlursAFocusedField() async throws {
    let model = TextModel()
    model.text = "fieldtext"
    let w = try harnessWindow(size: sz(400, 300)) {
        Column {
            Text(alpha).textSelection(.enabled)
            TextField("field", text: Binding(get: { model.text }, set: { model.text = $0 })).frame(width: 150)
        }
    }
    try await w.runUntilIdle()
    let field = try #require(w.window.lastHitboxes.first { $0.handlers.textInput != nil })
    w.click(at: pt(field.bounds.origin.x.value + 5, field.bounds.origin.y.value + 5))
    #expect(w.window.focusedElement != nil, "the field has focus")
    w.typeKey("a", modifierFlags: .primary)   // the field's own select-all
    try await press(w)
    #expect(w.window.focusedElement == nil, "the press blurred the field")
    w.typeKey("a", modifierFlags: .primary)
    w.platformWindow.clipboard = nil
    w.typeKey("c", modifierFlags: .primary)
    #expect(w.platformWindow.clipboard == alpha, "the Text's selection, not the field's: \(String(describing: w.platformWindow.clipboard))")
}

/// **5.7** A string change drops the selection; SwiftUI keeps a stale range (probe `S1`, divergence).
/// **Mutation:** keep the session on a changed string (⌘C then copies a range of the new string).
@Test @MainActor func aStringChangeDropsTheSelection() async throws {
    let model = TextModel()
    model.text = alpha
    let w = try harnessWindow(size: sz(400, 300)) {
        Column { Text(model.text).textSelection(.enabled) }
    }
    try await w.runUntilIdle()
    try await press(w)
    w.typeKey("a", modifierFlags: .primary)
    #expect(selected(w) == alpha)
    model.text = "ab"
    w.window.setNeedsRedraw(); try await w.runUntilIdle()
    #expect(w.window.textSelectionSession == nil, "the string changed")
    w.platformWindow.clipboard = nil
    w.typeKey("c", modifierFlags: .primary)
    #expect(w.platformWindow.clipboard == nil, "and nothing stale is copied")
}

/// **5.8** A selectable `Text` with a tap of its own selects and does not fire it, and an ancestor's tap does not fire over
/// the text (probe `G1`, `G2`; provisional until `HC-TXS-4`).
/// **Mutation:** the stage returns `false` for a press (the tap fires and the selection never starts).
@Test @MainActor func aSelectableTextWithATapSelectsAndDoesNotFireIt() async throws {
    let log = HarnessLog()
    let w = try harnessWindow(size: sz(400, 300)) {
        Column {
            Text("tap me").textSelection(.enabled).onTapGesture { log.add("own") }
            Column { Text("inside").textSelection(.enabled) }.frame(width: 200, height: 60).onTapGesture { log.add("ancestor") }
        }
    }
    try await w.runUntilIdle()
    w.click(at: at(w, 3, index: 0))
    #expect(log.entries.isEmpty, "the Text's own tap: \(log.entries)")
    #expect(w.window.textSelectionSession?.id == w.window.lastSelectableRegions[0].id)
    w.click(at: at(w, 3, index: 1))
    #expect(log.entries.isEmpty, "the ancestor's tap over the text: \(log.entries)")
    #expect(w.window.textSelectionSession?.id == w.window.lastSelectableRegions[1].id)
}

/// **5.9** A drag past the end of the text keeps selecting to its end: the session follows the pointer, not the hitbox.
/// **Mutation:** the drag stage requires the point inside the region.
@Test @MainActor func aDragPastTheTextSelectsToItsEnd() async throws {
    let w = try oneText()
    try await press(w)
    w.drag(from: try boundaryPoint(w, 6), to: pt(390, 290))
    try await w.runUntilIdle()
    #expect(selected(w) == "beta gamma delta", "\(String(describing: selected(w)))")
}

/// **5.10** A truncated `Text` selects and copies its whole string (probe `T1`).
/// **Mutation:** copy only the characters of the kept lines.
@Test @MainActor func aTruncatedTextCopiesItsWholeString() async throws {
    let w = try harnessWindow(size: sz(400, 300)) {
        Column { Text(alpha).lineLimit(1).textSelection(.enabled).frame(width: 60) }
    }
    try await w.runUntilIdle()
    try await press(w)
    w.typeKey("a", modifierFlags: .primary)
    w.typeKey("c", modifierFlags: .primary)
    #expect(w.platformWindow.clipboard == alpha)
}

/// **5.11** Edit › Copy and Select All: `chainClipboardCommands` adds Select All while a session exists (empty or not) and
/// Copy while a range does; both go with the session (probe `D1p`, `D1q`).
/// **Mutation:** add `.copy` whatever the range.
@Test @MainActor func editCopyIsEnabledWhileSelected() async throws {
    let w = try oneText()
    #expect(w.window.chainClipboardCommands.isEmpty)
    try await press(w)
    #expect(w.window.chainClipboardCommands == [.selectAll], "a session with no range: \(w.window.chainClipboardCommands)")
    w.typeKey("a", modifierFlags: .primary)
    #expect(w.window.chainClipboardCommands == [.selectAll, .copy])
    try await w.runUntilIdle()
    #expect(w.platformWindow.clipboardCommandRequests.last == [.selectAll, .copy], "the platform was told")
    w.window.dropTextSelection()
    #expect(w.window.chainClipboardCommands.isEmpty, "the session is gone")
}

/// **5.12** The right-click menu is `[Copy, Select All]`, Copy off with no range, and Copy copies; a declared `.contextMenu`
/// on the `Text` or an ancestor wins (probe `M1`, `M1e`; divergence).
/// **Mutation:** open the selection menu before looking for a declared one.
@Test @MainActor func aDeclaredContextMenuWinsOverTheCopyMenu() async throws {
    let w = try oneText()
    w.rightClick(at: at(w, 3))
    var menu = try #require(w.presentedMenu)
    #expect(menu.items.map(\.title) == ["Copy", "Select All"] && menu.items.map(\.isEnabled) == [false, true], "\(menu.items.map(\.title))")
    try w.chooseMenuItem("Select All")
    #expect(selected(w) == alpha)
    w.rightClick(at: at(w, 3))
    menu = try #require(w.presentedMenu)
    #expect(menu.items.map(\.isEnabled) == [true, true], "Copy is on with a range")
    w.platformWindow.clipboard = nil
    try w.chooseMenuItem("Copy")
    #expect(w.platformWindow.clipboard == alpha)

    let declared = try harnessWindow(size: sz(400, 300)) {
        Column { Text(alpha).textSelection(.enabled).contextMenu { Button("Mine") {} } }
    }
    try await declared.runUntilIdle()
    declared.rightClick(at: at(declared, 3))
    #expect(declared.presentedMenu?.items.map(\.title) == ["Mine"], "a declared menu wins")
    let ancestor = try harnessWindow(size: sz(400, 300)) {
        Column { Text(alpha).textSelection(.enabled) }.contextMenu { Button("Theirs") {} }
    }
    try await ancestor.runUntilIdle()
    ancestor.rightClick(at: at(ancestor, 3))
    #expect(ancestor.presentedMenu?.items.map(\.title) == ["Theirs"], "an ancestor's menu wins too")
}

/// **5.13** The highlight: a selected `Text` fills one rect per selected line, a caret-only session and other `Text`s fill
/// none, and a settled selected frame is one build with the same element requests as an unselected one.
/// **Mutation:** fill every line of the `Text`, not the selected ones.
@Test @MainActor func aSelectedIdleTextFillsOnlyItsRects() async throws {
    let w = try harnessWindow(size: sz(400, 300)) {
        Column {
            Text("one two three four five six seven eight nine ten").textSelection(.enabled).frame(width: 90)
            Text("other").textSelection(.enabled)
        }
    }
    try await w.runUntilIdle()
    let before = highlightFills(w)
    try await press(w)
    #expect(highlightFills(w) == before, "a caret-only session fills nothing")
    let idle = try await steadyFrame(w)
    w.typeKey("a", modifierFlags: .primary)
    try await w.runUntilIdle()
    let geometry = try #require(w.window.textSelectionSession?.geometry)
    #expect(geometry.lines.count > 2)
    #expect(highlightFills(w) - before == geometry.lines.count, "one fill per line: \(highlightFills(w) - before) of \(geometry.lines.count)")
    // One line only: a triple click on the first line fills exactly that line.
    let first = geometry.lines[0]
    let event = MouseEvent(position: pt(box(w).origin.x.value + 2, box(w).origin.y.value + Float(first.top + first.height / 2)),
                           modifiers: [], clickCount: 3, buttonNumber: 0, timestamp: w.now)
    w.send(.mouseDown(event)); w.send(.mouseUp(event)); w.tick()
    #expect(highlightFills(w) - before == 1, "one line selected, one fill: \(highlightFills(w) - before)")
    w.typeKey("a", modifierFlags: .primary)
    try await w.runUntilIdle()
    let steady = try await steadyFrame(w)
    #expect(steady.work.elementRequests == idle.work.elementRequests && steady.work.builds == 1,
            "\(steady.work.elementRequests) vs \(idle.work.elementRequests) requests, \(steady.work.builds) builds")
    #expect(steady.work.layoutMeasureCalls == idle.work.layoutMeasureCalls, "no layout work: the geometry is cached")
}

// MARK: 5b — retained replay (SB-X)

private struct RetainedCard: Component, @MainActor Equatable {
    var content: some ElementGroup {
        Column { Text(alpha).textSelection(.enabled) }.frame(width: 220, height: 40)
    }
    static func == (l: RetainedCard, r: RetainedCard) -> Bool { true }
}

/// **5b.1** A selectable `Text` inside a retained (`.equatable()`) subtree repaints its highlight: the occurrence misses
/// while its `Text` is selected, and once the selection drops it records and replays again, with no highlight.
/// **Mutation:** `retainedSubtreeHasPointerPressOrFocus` ignores the session (the selected frame replays without it).
@Test @MainActor func aRetainedSubtreeRepaintsTheHighlight() async throws {
    let w = try harnessWindow(size: sz(400, 300)) { Column { RetainedCard().equatable() } }
    try await w.runUntilIdle()
    for _ in 0..<2 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    w.resetFrameWork(); w.window.setNeedsRedraw(); try await w.runUntilIdle()
    let idle = totalWork(w)
    try await press(w)
    w.typeKey("a", modifierFlags: .primary)
    w.hover(at: pt(5, 295))   // off the card: only the selection keeps the occurrence from replaying (`SB-F` would anyway under the pointer)
    for _ in 0..<2 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    w.resetFrameWork(); w.window.setNeedsRedraw(); try await w.runUntilIdle()
    let selectedFrame = totalWork(w)
    #expect(selectedFrame.retainedHits == 0 && selectedFrame.retainedMisses >= 1,
            "the selected occurrence never replays: \(selectedFrame.retainedHits) hits, \(selectedFrame.retainedMisses) misses")
    #expect(highlightFills(w) == 1, "the highlight is painted every selected frame: \(highlightFills(w))")
    w.window.dropTextSelection()
    w.hover(at: pt(5, 295))   // the pointer left the card: a hovered occurrence never replays either (`SB-F`)
    for _ in 0..<3 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    w.resetFrameWork(); w.window.setNeedsRedraw(); try await w.runUntilIdle()
    #expect(totalWork(w).retainedHits == idle.retainedHits, "the dropped selection replays again: \(totalWork(w).retainedHits) vs \(idle.retainedHits)")
    #expect(highlightFills(w) == 0, "and no highlight")
}

// MARK: 5c — a retained pane holding an idle selectable Text (TXS-I item 3)

private struct PaneRow: Component {
    let index: Int
    var content: some ElementGroup { Text(verbatim: "setting \(index)").frame(width: 160) }
}

/// Alloy's shape: a mostly static pane (20 rows) holding one log `Text`, in an `.equatable()` component.
private struct Pane: Component, @MainActor Equatable {
    let selectable: Bool
    var content: some ElementGroup {
        Column {
            ForEach(0..<20, id: \.self) { PaneRow(index: $0) }
            if selectable { Text(verbatim: alpha).textSelection(.enabled) } else { Text(verbatim: alpha).textSelection(.disabled) }
        }
    }
    static func == (l: Pane, r: Pane) -> Bool { l.selectable == r.selectable }
}

/// The pane under a clickable square, so the pane's hitbox is not index 0 (a replay that forgets the base lands on the square's).
@MainActor private func paneWindow(selectable: Bool) throws -> TestWindow {
    try harnessWindow(size: sz(400, 4_000), options: .init(accessibilityClientActive: false)) {
        Column {
            Box().frame(width: 10, height: 10).onClick {}
            Pane(selectable: selectable).equatable()
        }
    }
}

@MainActor private func paneWork(selectable: Bool) async throws -> (work: FrameWork, hitboxes: Int, regions: Int) {
    try await steadyFrame(try paneWindow(selectable: selectable))
}

/// **5c.1** A retained (`.equatable()`) pane of 20 rows holding one enabled idle selectable `Text` costs what its flag-false twin
/// costs plus the one hitbox and region: the same requests, prepaints, paints, retained hits and prepaint hits, the occurrence's
/// prepaint replayed (not re-run) with the region recorded beside its hitbox.
/// **Mutation:** the region not carried by the ledger (the replay drops it: no region, the press finds nothing) and the old
/// refusal (`taint`: the prepaint runs in full every frame, `retainedPrepaintHits` 0).
@Test @MainActor func aRetainedPaneHoldingAnIdleSelectableTextReplaysLikeItsTwin() async throws {
    let off = try await paneWork(selectable: false), on = try await paneWork(selectable: true)
    #expect(on.work == off.work, "an enabled idle Text in a retained pane does the disabled twin's work")
    #expect(on.hitboxes == off.hitboxes + 1 && on.regions == 1 && off.regions == 0, "\(on.hitboxes) \(off.hitboxes) \(on.regions)")
    #expect(on.work.retainedPrepaintHits >= 1 && on.work.retainedGrafts == off.work.retainedGrafts, "its prepaint is replayed: \(on.work.retainedPrepaintHits)")
    #expect(on.work.elementRequests < 5 && on.work.retainedSkippedPrepaints >= 42,
            "the build was grafted and 42 prepaints stood for: \(on.work.elementRequests) requests, \(on.work.retainedSkippedPrepaints) skipped (the taint it replaced: 42 requests, 43 prepaints, none skipped)")
}

/// **5c.2** The replayed region still selects: with the pane replayed from its ledger, a press on its `Text` starts the session
/// (the region's hitbox index is the replay's, not the recording's), a drag selects and the real copy key writes the range.
/// **Mutation:** the replay appends the hitboxes but not the regions (no press finds a region); the replay keeps the recorded
/// index instead of rebasing it (the press finds the clickable square's hitbox, not the `Text`'s).
@Test @MainActor func aReplayedRegionStillSelects() async throws {
    let w = try paneWindow(selectable: true)
    let work = try await steadyFrame(w)
    try #require(work.work.retainedPrepaintHits >= 1, "the pane's prepaint is replayed")
    try #require(w.window.lastSelectableRegions.count == 1)
    // The click goes where the `Text` really is (its hitbox is the last registered), not where the region claims.
    let real = try #require(w.window.lastHitboxes.last).bounds
    w.click(at: pt(real.origin.x.value + 1, real.origin.y.value + 8))
    try await w.runUntilIdle(); w.tick()
    #expect(w.window.textSelectionSession?.id == w.window.lastSelectableRegions[0].id, "the press found the replayed region")
    w.drag(from: try boundaryPoint(w, 0), to: try boundaryPoint(w, 5))
    try await w.runUntilIdle()
    #expect(selected(w) == "alpha")
    w.typeKey("c", modifierFlags: .primary)
    #expect(w.platformWindow.clipboard == "alpha")
}

// MARK: 7 — accessibility

/// **7.1** While a client collects, every selectable `Text` answers the text-area state — `range == nil` with nothing
/// selected — and the selected one carries its UTF-16 range; a plain `Text` carries none.
/// **Mutation:** attach the state only to the selected `Text`.
@Test @MainActor func theSelectedTextPublishesItsRange() async throws {
    let w = try harnessWindow(size: sz(400, 300)) {
        Column {
            Text("first text A").textSelection(.enabled)
            Text("plain")
            Text("😀 second").textSelection(.enabled)
        }
    }
    try await w.runUntilIdle()
    func state(_ value: String) throws -> AccessibilityTextSelection?? {
        try w.accessibilityTree.nodes.values.first { $0.value == value }.map(\.textSelection)
    }
    #expect(try state("first text A") == .some(AccessibilityTextSelection(range: nil)), "selectable, nothing selected")
    #expect(try state("😀 second") == .some(AccessibilityTextSelection(range: nil)))
    #expect(try state("plain") == .some(nil), "a plain Text is not")
    try await press(w, 1)
    w.drag(from: try boundaryPoint(w, 0, index: 1), to: try boundaryPoint(w, 2, index: 1))   // the emoji and the space
    try await w.runUntilIdle()
    w.window.setNeedsRedraw(); try await w.runUntilIdle()
    #expect(try state("😀 second") == .some(AccessibilityTextSelection(range: 0..<3)),
            "grapheme 0..<2 is UTF-16 0..<3: \(String(describing: try? state("😀 second")))")
    #expect(try state("first text A") == .some(AccessibilityTextSelection(range: nil)), "the other stays unselected")
}

/// **7.2** Accessibility work happens only while a client collects: a window with no client publishes no tree and records
/// nothing, and the same tree with a client publishes the text-area state (`TXS-G`, `TXS-H`).
/// **Mutation:** the mark attached only to the selected `Text` (the loud arm reddens). A mark made without testing
/// `collectsAccessibility` is invisible here — with no client there is no tree and the record it would patch does not exist — and
/// is a finding, not a gap this arm can close: the record's own gate (`registerHandlers`) is what keeps a quiet window clean.
@Test @MainActor func theTextAreaStateIsRecordedOnlyForAClient() async throws {
    let quiet = try harnessWindow(size: sz(400, 300), options: .init(accessibilityClientActive: false)) {
        Column { Text("x").textSelection(.enabled) }
    }
    try await quiet.runUntilIdle()
    #expect(quiet.platformWindow.publishedAccessibilityTrees.isEmpty, "no client, no tree")
    #expect(quiet.window.lastSelectableRegions.count == 1, "the region is the pointer's and registers anyway")
    let loud = try harnessWindow(size: sz(400, 300)) { Column { Text("x").textSelection(.enabled) } }
    try await loud.runUntilIdle()
    let node = try loud.accessibilityTree.nodes.values.first { $0.value == "x" }
    #expect(node?.textSelection == AccessibilityTextSelection(range: nil))
}
