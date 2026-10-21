import Foundation
import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUITesting
@testable import MetalUI

// C14-f lane 1 (`RG-A`...`RG-C`, record 128): a `.onGeometryChange` scope inside an `.equatable()` occurrence no longer taints its
// prepaint ledger (`RK-E` item replaced): the ledger records each note, an equal-key replay re-notes it into the lifecycle store, and a
// translated replay of a ledger holding a note is refused by name `geometryTranslated`. Counts and delivered values only.
// Red on arrival at 99b21a1c: test 1 (the taint), test 5 (no ledger to refuse).

@MainActor final class RGLog {
    var entries: [String] = []
}

@MainActor final class RGModel {
    var pad: Float = 10
    var scale: Double = 1
    var tag = 0
}

private func rgDescribe(_ p: GeometryProxy) -> String {
    let f = p.frame(in: .global)
    return "\(f.origin.x.value),\(f.origin.y.value) \(f.size.width.value)x\(f.size.height.value)"
}

/// One observed card. `stacked` adds a second scope at the same position whose value differs (width only).
private struct RGCard: Component, @MainActor Equatable {
    let id: Int
    let stacked: Bool
    let log: RGLog
    /// Changes the card's value so its content and ledger are made again while its geometry is the same.
    let tag: Int
    static func == (l: RGCard, r: RGCard) -> Bool { l.id == r.id && l.stacked == r.stacked && l.tag == r.tag }
    var content: some ElementGroup {
        if stacked {
            Box().frame(width: Pixels(40), height: Pixels(20)).background(.accent)
                .onGeometryChange(for: String.self, of: { rgDescribe($0) }) { log.entries.append("A\(id):\($0)") }
                .onGeometryChange(for: Float.self, of: { $0.size.width.value }) { log.entries.append("B\(id):\($0)") }
        } else {
            Box().frame(width: Pixels(40), height: Pixels(20)).background(.accent)
                .onGeometryChange(for: String.self, of: { rgDescribe($0) }) { log.entries.append("A\(id):\($0)") }
        }
    }
}

private enum RGKind { case plain, scrolled, effect, offsetEffect }

private struct RGRoot: Component {
    let model: RGModel
    let log: RGLog
    let kind: RGKind
    var stacked = false
    var content: some ElementGroup {
        switch kind {
        case .plain:
            VStack(spacing: 2) {
                Color(red: 0.5, green: 0.5, blue: 0.5).frame(height: Pixels(model.pad))
                RGCard(id: 0, stacked: stacked, log: log, tag: model.tag).equatable()
                RGCard(id: 1, stacked: stacked, log: log, tag: model.tag).equatable()
            }
        case .scrolled:
            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    Color(red: 0.5, green: 0.5, blue: 0.5).frame(height: Pixels(model.pad))
                    RGCard(id: 0, stacked: stacked, log: log, tag: model.tag).equatable()
                    RGCard(id: 1, stacked: stacked, log: log, tag: model.tag).equatable()
                    Color(red: 0.5, green: 0.5, blue: 0.5).frame(height: Pixels(400))
                }
            }.frame(width: Pixels(150), height: Pixels(120))
        case .effect:
            VStack(spacing: 2) {
                RGCard(id: 0, stacked: stacked, log: log, tag: model.tag).equatable()
                RGCard(id: 1, stacked: stacked, log: log, tag: model.tag).equatable()
            }.scaleEffect(model.scale)
        case .offsetEffect:
            VStack(spacing: 2) {
                RGCard(id: 0, stacked: stacked, log: log, tag: model.tag).equatable()
                RGCard(id: 1, stacked: stacked, log: log, tag: model.tag).equatable()
            }.offset(x: Pixels(model.pad), y: 0)
        }
    }
}

@MainActor
private func rgWindow(_ kind: RGKind, stacked: Bool = false, retained: Bool = true) throws
    -> (TestWindow, RGModel, RGLog) {
    let model = RGModel(), log = RGLog()
    let w = try TestWindow(size: Size(width: Pixels(200), height: Pixels(260))) {
        VStack(spacing: 0) { RGRoot(model: model, log: log, kind: kind, stacked: stacked) }
    }
    w.window.testingRetainedSubtrees = retained
    return (w, model, log)
}

@MainActor private func rgRedraw(_ w: TestWindow, _ n: Int = 1) {
    for _ in 0..<n { w.window.setNeedsRedraw(); w.tick() }
}

private let rgVerifyNote: Comment =
    "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay counts this test pins are not its to read"

private var rgVerifying: Bool {
    ProcessInfo.processInfo.environment["METALUI_VERIFY_RETAINED"] == "1"
}

/// 1 (`RG-A`). Two observed cards in `.equatable()` occurrences: on a steady frame neither taints its ledger by name
/// `geometryChange` and both prepaints are skipped. Red at 99b21a1c (`reasons["geometryChange"] == 2`, hits 0).
/// Mutation: restore `prepaintLog?.taint("geometryChange")` in `Frame.noteGeometry`.
@Test(.enabled(if: !rgVerifying, rgVerifyNote)) @MainActor
func aGeometryScopeInAnEquatableOccurrenceDoesNotTaintItsLedger() throws {
    let (w, _, _) = try rgWindow(.plain)
    rgRedraw(w, 6)
    let f = w.lastFrameWork
    #expect(f.retainedIneligibleReasons["geometryChange", default: 0] == 0, "\(f.retainedIneligibleReasons)")
    #expect(f.retainedPrepaintIneligible == 0, "\(f.retainedPrepaintIneligible)")
    #expect(f.retainedPrepaintHits == 2, "both prepaints replay: \(f.retainedPrepaintHits)")
}

/// 2 (`RG-A`). The initial value is delivered once per card; any number of steady (replayed) frames deliver nothing more.
/// Mutation: drop the re-note in `replayPrepaintLedger` (the next build reports `initial` again, G7).
@Test @MainActor
func aReplayedGeometryNoteDeliversNothingUntilTheValueChanges() throws {
    let (w, model, log) = try rgWindow(.plain)
    rgRedraw(w, 12)
    #expect(log.entries.count == 2, "\(log.entries)")
    if !rgVerifying { #expect(w.lastFrameWork.retainedPrepaintHits == 2) }
    // A card made again (its value changed, its geometry did not) notes fresh: the store must still hold the replayed key, or
    // it reports the same value as an `initial` (G7).
    model.tag += 1
    rgRedraw(w, 3)
    #expect(log.entries.count == 2, "a re-made card with an equal value delivers nothing: \(log.entries)")
}

/// The delivered values over a script (resize, scroll, shift), for a window with retention `retained`.
@MainActor private func rgScript(retained: Bool) throws -> [String] {
    let (w, model, log) = try rgWindow(.scrolled, retained: retained)
    var out: [String] = []
    func step(_ name: String, _ act: () -> Void) {
        let before = log.entries.count
        act()
        out.append("\(name): \(log.entries[before...].joined(separator: " | "))")
    }
    rgRedraw(w, 6)
    out.append("warm: \(log.entries.joined(separator: " | "))")
    step("steady") { rgRedraw(w, 3) }
    step("resize") { w.resize(to: Size(width: Pixels(240), height: Pixels(300))); rgRedraw(w, 2) }
    step("scroll") { w.scroll(at: Point(x: Pixels(40), y: Pixels(40)), byDeltaX: 0, deltaY: -10); rgRedraw(w, 2) }
    step("shift") { model.pad += 4; rgRedraw(w, 3) }
    step("scroll2") { w.scroll(at: Point(x: Pixels(40), y: Pixels(40)), byDeltaX: 0, deltaY: 6); rgRedraw(w, 2) }
    step("resize2") { w.resize(to: Size(width: Pixels(200), height: Pixels(260))); rgRedraw(w, 2) }
    step("steady2") { rgRedraw(w, 3) }
    return out
}

/// 3 (`RG-B`). Retention on delivers exactly the values, in the order, a window with retention off does over a script.
/// Mutation: replay with the previous frame's size (re-note a stale value in `replayPrepaintLedger`).
@Test @MainActor
func theDeliveredValuesEqualAFreshWindowsOverAScript() throws {
    let on = try rgScript(retained: true)
    let off = try rgScript(retained: false)
    #expect(on == off, "\non:  \(on)\noff: \(off)")
    #expect(on.contains { $0.hasPrefix("shift: A") }, "the shift delivers: \(on)")
}

/// 4 (`RG-A`). A `.scaleEffect` above the occurrences changes: the ledger misses (no prepaint hit that frame) and the new value is
/// delivered, equal to a fresh window's. Mutation: leave the effect out of the ambient comparison in `PrepaintKey`.
@Test(.enabled(if: !rgVerifying, rgVerifyNote)) @MainActor
func aGeometryNoteUnderAChangedRenderEffectMissesAndDelivers() throws {
    func run(retained: Bool) throws -> (log: [String], hits: Int) {
        let (w, model, log) = try rgWindow(.effect, retained: retained)
        rgRedraw(w, 6)
        log.entries.removeAll()
        model.scale = 1.5
        rgRedraw(w, 1)
        let hits = w.lastFrameWork.retainedPrepaintHits
        rgRedraw(w, 2)
        return (log.entries, hits)
    }
    let on = try run(retained: true), off = try run(retained: false)
    #expect(on.log == off.log, "\(on.log) vs \(off.log)")
    #expect(on.log.count == 2, "both cards report the scaled frame: \(on.log)")
    #expect(on.hits == 0, "the changed effect misses: \(on.hits)")
}

/// 5 (`RG-C`, superseded by `RL-E`). A whole-pixel shift of the occurrences (the header above grows 4 points; offset, size and effect
/// unchanged) is a translation: the ledger holds a geometry note, which is now **recomputed** (the proxy rebuilt at the moved frame, the
/// transform run again), not refused: no `geometryTranslated` is counted, both prepaints replay, the values delivered equal a fresh
/// window's and no frame is redone. At `RG-C` this pinned the refusal by name (2); the supersession is pinned by
/// `RetainedTranslationCarryTests` 12-16. Mutation: restore the refusal in `movedPrepaintLedger`.
@Test(.enabled(if: !rgVerifying, rgVerifyNote)) @MainActor
func aTranslatedReplayOfAGeometryNoteIsRecomputedNotRefused() throws {
    func run(retained: Bool) throws -> (log: [String], refused: Int, redos: Int, hits: Int) {
        let (w, model, log) = try rgWindow(.plain, retained: retained)
        rgRedraw(w, 6)
        log.entries.removeAll()
        w.resetFrameWork()
        model.pad += 4
        rgRedraw(w, 1)
        let refused = w.frameWork.reduce(0) { $0 + $1.retainedTranslationRefusedReasons["geometryTranslated", default: 0] }
        let redos = w.frameWork.reduce(0) { $0 + $1.retainedRedos }
        let hits = w.frameWork.reduce(0) { $0 + $1.retainedPrepaintHits }
        rgRedraw(w, 2)
        return (log.entries, refused, redos, hits)
    }
    let on = try run(retained: true), off = try run(retained: false)
    #expect(on.log == off.log, "\(on.log) vs \(off.log)")
    #expect(on.log.count == 2, "both cards moved: \(on.log)")
    #expect(on.refused == 0, "recomputed, not refused: \(on.refused)")
    #expect(on.hits == 2, "both prepaints replay translated: \(on.hits)")
    #expect(on.redos == 0, "\(on.redos)")
}

/// 6 (`RG-A`). Two scopes stacked at one position are two store keys (`$geometry<depth>`), and the ledger holds both: steady replayed
/// frames deliver nothing, and a card made again with an equal geometry reports nothing for either scope (a scope the replay
/// left out would report its value as `initial`, G7). The order the notes replay in is unobservable (the keys differ and only a
/// changed note makes an event, `RG-K`), so reversing it is an equivalent mutation. Mutation: replay only the first recorded note.
@Test @MainActor
func twoGeometryScopesStackedAtOnePositionAreBothHeldThroughAReplay() throws {
    let (w, model, log) = try rgWindow(.plain, stacked: true)
    rgRedraw(w, 6)
    #expect(log.entries.count == 4, "A and B for both cards, once: \(log.entries)")
    log.entries.removeAll()
    rgRedraw(w, 6)
    #expect(log.entries.isEmpty, "steady replayed frames deliver nothing: \(log.entries)")
    if !rgVerifying { #expect(w.lastFrameWork.retainedPrepaintHits == 2) }
    model.tag += 1
    rgRedraw(w, 3)
    #expect(log.entries.isEmpty, "a re-made card with equal geometry reports neither scope: \(log.entries)")
}

/// 7 (`RG-C`, checker; superseded by `RL-E`). An `.offset` above the occurrences moves by whole pixels (the effect translation of
/// `FS-O`, no layout move): the ledger holds a geometry note, which the effect-translated replay recomputes against the current effect
/// (`translatedGeometryNotes`) instead of refusing it at `replayPrepaintLedger`'s site; no `geometryTranslated` is counted, both
/// prepaints replay and the values delivered equal a fresh window's. Mutation: restore the refusal in `retainedPrepaintDecision`'s
/// effect branch.
@Test(.enabled(if: !rgVerifying, rgVerifyNote)) @MainActor
func anEffectTranslatedReplayOfAGeometryNoteIsRecomputedNotRefused() throws {
    func run(retained: Bool) throws -> (log: [String], refused: Int, hits: Int) {
        let (w, model, log) = try rgWindow(.offsetEffect, retained: retained)
        rgRedraw(w, 6)
        log.entries.removeAll()
        w.resetFrameWork()
        model.pad += 4
        rgRedraw(w, 1)
        let refused = w.frameWork.reduce(0) { $0 + $1.retainedTranslationRefusedReasons["geometryTranslated", default: 0] }
        let hits = w.frameWork.reduce(0) { $0 + $1.retainedPrepaintHits }
        rgRedraw(w, 2)
        return (log.entries, refused, hits)
    }
    let on = try run(retained: true), off = try run(retained: false)
    #expect(on.log == off.log, "\(on.log) vs \(off.log)")
    #expect(on.log.count == 2, "both cards moved: \(on.log)")
    #expect(on.refused == 0, "recomputed, not refused: \(on.refused)")
    #expect(on.hits == 2, "both prepaints replay: \(on.hits)")
}
