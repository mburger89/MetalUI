import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Testing
@testable import MetalUI

// C14-e lane 1 (`CF-A`, record 127): `\.textMeasurer` is a comparable `EnvironmentReading` (the text system's
// instance plus the two resolved default text styles), so an `.equatable()` component that reads it is skipped
// while neither changed. Tests T1-T5 of `docs/superpowers/specs/2026-10-20-warm-settle-design.md` §3. Counts, never time.

private let tmUnbounded = Size(width: Pixels(Float.infinity), height: Pixels(Float.infinity))

@MainActor final class TMModel { var big = false }
@MainActor final class TMLog { var n = 0; var width: Float = 0 }

/// An `.equatable()` reader of the measurer: it sizes a label and shows the measured width.
private struct TMReader: Component, @MainActor Equatable {
    let log: TMLog
    @Environment(\.textMeasurer) var measurer
    var content: some ElementGroup {
        let _ = log.n += 1
        let width = measurer.resolve(Text("12.5 mm")).measure(in: tmUnbounded).width
        let _ = log.width = width.value
        Text("w\(Int(width.value))").frame(width: Pixels(120), height: Pixels(16))
    }
    static func == (l: TMReader, r: TMReader) -> Bool { l.log === r.log }
}

/// T1 — a measurer reader is skipped while the system is unchanged. **Red before (679f5d7d):** one refusal and no
/// skip per frame. Mutations: `Environment.init`/`.of` bypass the arm (refused again); the arm keyed on the per-frame
/// box (evaluated every frame).
@Test @MainActor func aMeasurerReaderIsSkippedWhileTheSystemIsUnchanged() throws {
    let log = TMLog()
    let window = try harnessWindow { VStack(spacing: 0) { TMReader(log: log).equatable() } }
    for _ in 0..<3 { _ = eeRedraw(window) }
    log.n = 0
    for index in 0..<3 {
        let f = eeRedraw(window)
        #expect(f.contentSkips == 1 && f.contentEvaluations == 0 && f.contentRefusals == 0,
                "frame \(index): skips \(f.contentSkips) evaluations \(f.contentEvaluations) refusals \(f.contentRefusals)")
    }
    #expect(log.n == 0, "the getter did not run: \(log.n)")
}

/// T2 — a font change above a measurer reader re-evaluates it and the shown size follows. Mutation: the style half
/// of the reading dropped (the width stays stale).
@Test @MainActor func aFontChangeAboveAMeasurerReaderReevaluatesIt() throws {
    let log = TMLog(), model = TMModel()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            VStack(spacing: 0) { TMReader(log: log).equatable() }
                .font(model.big ? Font.system(size: 26) : Font.system(size: 13))
        }
    }
    for _ in 0..<3 { _ = eeRedraw(window) }
    let small = log.width
    try #require(small > 0)
    log.n = 0
    model.big = true
    var f = eeRedraw(window)
    #expect(f.contentEvaluations == 1 && f.contentSkips == 0 && f.contentRefusals == 0, "a font change evaluates once")
    let big = log.width
    #expect(big > small * 1.5, "the measured width follows the font: \(small) then \(big)")
    model.big = false
    f = eeRedraw(window)
    #expect(f.contentEvaluations == 1, "and back")
    #expect(log.width == small)
    #expect(log.n == 2)
}

/// T3 — the reading changes with each text-style field of the environment and with nothing else. Mutation (per
/// argument): that field removed from what the reading resolves.
private enum TMField: String, CaseIterable { case font, fontWeight, italic, controlSize, lineLimit, truncation, alignment, foreground }

@Test(arguments: TMField.allCases) @MainActor fileprivate func aMeasurerReadingChangesWithEachTextStyleField(field: TMField) {
    let box = TextSystemBox(harnessTextSystem())
    var base = EnvironmentValues()
    base.textSystemBox = box
    var changed = base
    switch field {
    case .font: changed.font = .system(size: 20)
    case .fontWeight: changed.fontWeight = .bold
    case .italic: changed.italic = true
    case .controlSize: changed.controlSize = .small
    case .lineLimit: changed.textLineLimit = TextLineLimit(min: nil, max: 2)
    case .truncation: changed.truncationMode = .middle
    case .alignment: changed.multilineTextAlignment = .center
    case .foreground: changed.foregroundStyle = .red
    }
    #expect(EnvironmentReading.of(base.textMeasurer) == .of(base.textMeasurer), "equal environments read equal")
    #expect(EnvironmentReading.of(base.textMeasurer) != .of(changed.textMeasurer), "\(field) changes the reading")
}

/// T3b — an environment field the measurer never resolves does not change the reading. Mutation: the whole
/// environment compared.
@Test @MainActor func aFieldTheMeasurerNeverResolvesDoesNotChangeTheReading() {
    let box = TextSystemBox(harnessTextSystem())
    var a = EnvironmentValues(); a.textSystemBox = box
    var b = a; b.colorScheme = .dark; b.isEnabled = false
    #expect(EnvironmentReading.of(a.textMeasurer) == .of(b.textMeasurer))
}

/// T4 — the reading is the system instance, not the per-frame box. Mutation: keyed on `ObjectIdentifier(box)`.
@Test @MainActor func theReadingIsTheSystemInstanceNotTheBox() {
    let system = harnessTextSystem(), other = harnessTextSystem()
    func measurer(_ box: TextSystemBox?) -> EnvironmentReading {
        var values = EnvironmentValues(); values.textSystemBox = box
        return .of(values.textMeasurer)
    }
    #expect(measurer(TextSystemBox(system)) == measurer(TextSystemBox(system)), "two boxes over one system")
    #expect(measurer(TextSystemBox(system)) != measurer(TextSystemBox(other)), "two systems")
    #expect(measurer(nil) == measurer(nil), "no box equals itself")
    #expect(measurer(nil) != measurer(TextSystemBox(system)))
}

/// T5 — a measurer reader is eligible for retention: its subtree hits, and the scene equals a retention-off frame;
/// a font change repaints. Mutation: the reading uncomparable (the subtree is refused, no hit).
@Test @MainActor func aMeasurerReaderReplaysItsPaint() throws {
    let log = TMLog(), model = TMModel()
    func make(retained: Bool) throws -> TestWindow {
        let window = try harnessWindow {
            VStack(spacing: 0) {
                VStack(spacing: 0) { TMReader(log: log).equatable() }
                    .font(model.big ? Font.system(size: 26) : Font.system(size: 13))
            }
        }
        window.window.testingRetainedSubtrees = retained
        return window
    }
    let on = try make(retained: true), off = try make(retained: false)
    for _ in 0..<4 { _ = eeRedraw(on); _ = eeRedraw(off) }
    let f = eeRedraw(on); _ = eeRedraw(off)
    #expect(f.retainedHits >= 1, "the reader's subtree replays: hits \(f.retainedHits) ineligible \(f.retainedIneligible)")
    #expect(eeSceneBytes(on) == eeSceneBytes(off))
    model.big = true
    _ = eeRedraw(on); _ = eeRedraw(off)
    #expect(eeSceneBytes(on) == eeSceneBytes(off), "a font change repaints")
}
