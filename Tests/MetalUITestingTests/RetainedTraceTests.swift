import Foundation
@testable import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
#if canImport(Darwin)
import MetalUITestSupport
#endif
import Testing

// C14-j lane 1 (`DM-E`, `DM-F`): `METALUI_TRACE_RETAINED=1` names every failing conjunct of the paint and the prepaint decision, says
// which decision a line is about, prints a path long enough to identify an occurrence and the writer behind an `observed`. Every
// test reads the package sink (`RetainedTrace.sink`), never stdout. Counts and strings, never time.
//
// **Red before the change** (measured, record 140): the first six do not compile (no `RetainedTrace`, `PaintInvalidation`,
// `PrepaintInvalidation`, `describeDifference` on `ReplayKey`); the pre-change `traceMiss` printed `[]` for coverage, ledger
// identity, `RW-S`, `nodeCount` and `shapeInterior`.

/// Collects the sink's lines for the length of `body`, restoring the sink after.
@MainActor func collectTrace(_ body: () throws -> Void) rethrows -> [String] {
    var lines: [String] = []
    RetainedTrace.sink = { lines.append($0) }
    defer { RetainedTrace.sink = nil }
    try body()
    return lines
}

/// The reasons a trace line prints: the text between `reasons=[` and the next `]`.
func traceReasons(_ line: String) -> [String]? {
    guard let open = line.range(of: "reasons=["), let close = line[open.upperBound...].firstIndex(of: "]") else { return nil }
    return line[open.upperBound..<close].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
}

// MARK: 1 - each paint conjunct alone

enum PaintConjunct: String, CaseIterable, Sendable, CustomStringConvertible {
    case observed, serial, coverageBuild = "coverage.build", coveragePrepaint = "coverage.prepaint", versions, pointer
    case ledgerIdentity = "ledger.identity", ledgerGain = "ledger.gain"
    var description: String { rawValue }
    var inputs: PaintInvalidation.Inputs {
        var i = PaintInvalidation.Inputs()
        switch self {
        case .observed: i.observedChange = true
        case .serial: i.serialMatches = false
        case .coverageBuild: i.coverageBuild = false
        case .coveragePrepaint: i.coveragePrepaint = false
        case .versions: i.versionsUnchanged = false
        case .pointer: i.underPointer = true
        case .ledgerIdentity: i.ledgerIdentityDiffers = true
        case .ledgerGain: i.ledgerGain = true
        }
        return i
    }
}

/// Each conjunct of the paint decision's `valid` fails alone and is named alone; with none failing the decision is valid and the
/// list is empty (the control). **Mutations:** delete a case's `if` from `PaintInvalidation.names` (reddens that argument only);
/// swap `coverage.build` and `coverage.prepaint` (reddens both of theirs).
@Test(arguments: PaintConjunct.allCases)
func thePaintTraceNamesEachConjunctWhenItFailsAlone(conjunct: PaintConjunct) {
    let failing = PaintInvalidation(conjunct.inputs)
    #expect(failing.names == [conjunct.rawValue], "\(conjunct): \(failing.names)")
    #expect(!failing.isValid)
    let control = PaintInvalidation(PaintInvalidation.Inputs())
    #expect(control.isValid && control.names.isEmpty, "the control names nothing: \(control.names)")
}

// MARK: 4 - each prepaint guard alone

enum PrepaintConjunct: String, CaseIterable, Sendable, CustomStringConvertible {
    case replayDisallowed, quarantine, noRecord, noLedger, observed, coverageBuild = "coverage.build", coveragePrepaint = "coverage.prepaint", serial
    case versions, pointerInLedger
    var description: String { rawValue }
    var inputs: PrepaintInvalidation.Inputs {
        var i = PrepaintInvalidation.Inputs()
        switch self {
        case .replayDisallowed: i.replayDisallowed = true
        case .quarantine: i.quarantined = true
        case .noRecord: i.hasRecord = false
        case .noLedger: i.hasLedger = false
        case .observed: i.observedChange = true
        case .coverageBuild: i.coverageBuild = false
        case .coveragePrepaint: i.coveragePrepaint = false
        case .serial: i.serialMatches = false
        case .versions: i.versionsUnchanged = false
        case .pointerInLedger: i.pointerInLedger = true
        }
        return i
    }
}

/// The prepaint decision's guard names each failing conjunct alone. **Mutations:** as test 1.
@Test(arguments: PrepaintConjunct.allCases)
func thePrepaintTraceNamesTheFailingGuard(conjunct: PrepaintConjunct) {
    let failing = PrepaintInvalidation(conjunct.inputs)
    #expect(failing.names == [conjunct.rawValue], "\(conjunct): \(failing.names)")
    #expect(!failing.isReplayable)
    let control = PrepaintInvalidation(PrepaintInvalidation.Inputs())
    #expect(control.isReplayable && control.names.isEmpty, "the control names nothing: \(control.names)")
}

// MARK: Key differences, every field

private func replayKey() -> ReplayKey {
    ReplayKey(rects: [1, 2, 3, 4], interior: 7, shapeInterior: 8, nodeCount: 3,
              ambient: AmbientKey(clip: [0, 0, 10, 10], offset: [0, 0], layerOpacityScale: [1], depths: [0], scopes: [],
                                  environment: EnvironmentValues().retainedFingerprint, snappingTransaction: false, disablesAnimations: false))
}

/// A `ReplayKey` field changed alone is named by `describeDifference`, for every stored field of the key and of its ambient;
/// the Mirror counts make a new field owe a row here and in the function (`DM-D`). **Mutation:** remove `key.nodeCount` from
/// `describeDifference` (reddens the `nodeCount` arm).
@Test @MainActor
func everyReplayKeyFieldIsNamedWhenItDiffersAlone() throws {
    let base = replayKey()
    try #require(Mirror(reflecting: base).children.count == 5, "a new ReplayKey field owes a row in describeDifference and here")
    try #require(Mirror(reflecting: base.ambient).children.count == 8, "a new AmbientKey field owes a row in describeDifference and here")
    var cases: [(String, (inout ReplayKey) -> Void)] = [
        ("key.rects", { $0.rects = [9] }), ("key.interior", { $0.interior += 1 }), ("key.shapeInterior", { $0.shapeInterior += 1 }),
        ("key.nodeCount", { $0.nodeCount += 1 }),
        ("key.ambient.clip", { $0.ambient.clip = [1] }), ("key.ambient.offset", { $0.ambient.offset = [5, 5] }),
        ("key.ambient.layerOpacityScale", { $0.ambient.layerOpacityScale = [0.5] }), ("key.ambient.depths", { $0.ambient.depths = [1] }),
        ("key.ambient.scopes", { $0.ambient.scopes = [[1]] }),
        ("key.ambient.snappingTransaction", { $0.ambient.snappingTransaction = true }),
        ("key.ambient.disablesAnimations", { $0.ambient.disablesAnimations = true }),
    ]
    cases.append(("key.ambient.environment", { $0.ambient.environment.isEnabled.toggle() }))
    for (name, change) in cases {
        var k = base; change(&k)
        #expect(base != k, "\(name): the mutation changes the key")
        #expect(k.describeDifference(from: base) == [name], "\(name): \(k.describeDifference(from: base))")
    }
    #expect(base.describeDifference(from: base).isEmpty)
}

// MARK: Path tail

/// The path tail is 120 characters by default and as long as `pathLength` says. **Mutation:** `suffix(60)` in `tail`.
@Test
func thePathSuffixIsAtLeast120ByDefaultAndConfigurable() {
    let path = String(repeating: "positional(0)/", count: 20)   // 280 characters
    #expect(RetainedTrace.defaultPathLength >= 120)
    #expect(RetainedTrace.tail(of: path, length: RetainedTrace.defaultPathLength).count == RetainedTrace.defaultPathLength)
    #expect(RetainedTrace.tail(of: path, length: 200).count == 200)
    #expect(RetainedTrace.tail(of: "short", length: 120) == "short")
    #expect(RetainedTrace.tail(of: path, length: 50) == String(path.suffix(50)))
}

// MARK: Window level

@Suite(.serialized) @MainActor
struct RetainedTraceWindowTests {
    private func missLines(_ lines: [String]) -> [String] { lines.filter { $0.hasPrefix("retained paint miss") || $0.hasPrefix("retained prepaint miss") } }

    /// 2 - a fixture's change frame names `serial` (both arms: the observed arm's getter session fires first and re-evaluates) and, for the observed arm, the writer; every line says
    /// `paint` or `prepaint`; the frame after a change misses nothing (lane 2, `DM-C`; it named a coverage half before, the second miss of `DM-B`). **Mutations:** `retainedPaintDecision` reading a private `valid` instead of
    /// `PaintInvalidation` (the lines disagree with the decision: `unclassified`); no coverage name (reddens the second arm).
    @Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss")) func aChangeNamesItsConjuncts() throws {
        for arm in [DMArm.value, .observed] {
            let (window, model) = try doubleMissWindow(arm)
            RetainedTrace.unclassified = 0
            let change = collectTrace { _ = doubleMissStep(window, model, arm: arm, changed: [1, 4], to: 3) }
            let paintMisses = missLines(change).filter { $0.hasPrefix("retained paint miss") }
            try #require(!paintMisses.isEmpty, "\(arm): a change misses")
            let named = paintMisses.compactMap(traceReasons)
            #expect(named.count == paintMisses.count && named.allSatisfy { !$0.isEmpty }, "\(arm): no empty list: \(paintMisses)")
            #expect(RetainedTrace.unclassified == 0)
            switch arm {
            case .value: #expect(named.contains { $0.contains("serial") }, "value arm names serial: \(paintMisses)")
            case .observed:
                // The getter's own session fires first and re-evaluates the getter: the miss names `serial` and the writer.
                #expect(named.contains { $0.contains("serial") }, "observed arm names serial: \(paintMisses)")
                #if DEBUG
                #expect(paintMisses.contains { $0.contains("cause:") && $0.contains("radius") }, "the writer is named: \(paintMisses)")
                #endif
            case .ledgerGain, .moved, .nested: break
            }
            // `DM-C`: the change frame observes, so the frame after hits and no line names a coverage half (it did before lane 2).
            #expect(!named.contains { $0.contains("coverage.build") || $0.contains("coverage.prepaint") }, "\(arm): no coverage miss after a change: \(paintMisses)")
            #expect(paintMisses.count == 2, "\(arm): one miss line per changed occurrence: \(paintMisses)")
        }
    }

    /// 3 - no miss line ever has an empty reason list, on the bracket (`.value`, `.panels`), the zoom and the fillet-drag fixtures
    /// and the three double-miss arms; the unclassified counter stays zero. **Mutation:** remove `key.nodeCount` from
    /// `describeDifference` and the unit arm of `everyReplayKeyFieldIsNamedWhenItDiffersAlone` reddens; here, delete the
    /// coverage names (the second frame of a change prints `unclassified`).
    @Test func noMissLineEverHasAnEmptyReasonList() async throws {
        RetainedTrace.unclassified = 0
        var all: [String] = []
        all += collectTrace { for arm in [BracketArm.value, .panels] { _ = try? bracketOrbitFrames(arm: arm, frames: 4) } }
        all += collectTrace {
            for arm in [FDArm.sliderOutside, .sliderEverywhere, .observedRead] {
                if let (w, m) = try? filletDragWindow(arm) { _ = try? fdDrag(w, model: m, steps: 4) }
            }
        }
        for arm in DMArm.allCases {
            all += collectTrace {
                if let (w, m) = try? doubleMissWindow(arm) { for k in 0..<3 { _ = doubleMissStep(w, m, arm: arm, changed: [k, k + 3], to: Double(k + 2)) } }
            }
        }
        let zoom = try zoomPair()
        var zoomLines: [String] = []
        RetainedTrace.sink = { zoomLines.append($0) }
        for scale in [Float(1.2), 1.5, 1.8] { await zoomStep(zoom, to: scale) }
        RetainedTrace.sink = nil
        all += zoomLines
        let misses = missLines(all)
        try #require(!misses.isEmpty, "the fixtures miss somewhere")
        for line in misses {
            let reasons = traceReasons(line)
            #expect(reasons?.isEmpty == false, "empty reason list: \(line)")
        }
        #expect(RetainedTrace.unclassified == 0, "unclassified misses: \(RetainedTrace.unclassified)")
        #expect(all.allSatisfy { !$0.hasPrefix("retained miss") }, "every decision line says paint or prepaint")
    }

    /// 5 - the writer behind an `observed` is named. Debug only: a release build inlines the setter (`DM-E`, probe
    /// `observation-fire-cause.swift`). **Mutation:** capture nothing in `writerCause`.
    @Test(.enabled(if: debugBuild, "release inlines the observable setter: the cause is `?` there (DM-E)"))
    func theFireCauseNamesTheWritingProperty() throws {
        let (window, model) = try doubleMissWindow(.observed)
        let lines = collectTrace { _ = doubleMissStep(window, model, arm: .observed, changed: [2], to: 4) }
        let cause = lines.first { $0.contains("cause:") }
        #expect(cause?.contains("radius.setter") == true, "cause names the property: \(lines.filter { $0.contains("miss") })")
    }

    /// 6 - the trace costs nothing when off: no line is built (`linesBuilt` stays 0) and a changed frame allocates less than
    /// with a sink (Darwin; `PA-J`: thread-filtered, differential). **Mutation:** remove the `active` guard from `emit` and from `missLine`/`phaseFlags` together (either alone is a redundant layer; the `pathsBuilt` read reddens, the allocation differential alone did not).
    #if canImport(Darwin)
    @Test func theTraceCostsNothingWhenOff() throws {
        let (offWindow, offModel) = try doubleMissWindow(.value)
        RetainedTrace.linesBuilt = 0
        RetainedTrace.pathsBuilt = 0
        let off = countAllocations { _ = doubleMissStep(offWindow, offModel, arm: .value, changed: [1, 4], to: 3) }
        #expect(RetainedTrace.linesBuilt == 0, "sink nil and the environment unset: no line is built (\(RetainedTrace.linesBuilt))")
        #expect(RetainedTrace.pathsBuilt == 0, "sink nil and the environment unset: no path is rendered (\(RetainedTrace.pathsBuilt)); a removed `active` guard in a builder or in `emit` reddens this")
        let (onWindow, onModel) = try doubleMissWindow(.value)
        var sunk = 0
        RetainedTrace.sink = { _ in sunk += 1 }
        let on = countAllocations { _ = doubleMissStep(onWindow, onModel, arm: .value, changed: [1, 4], to: 3) }
        RetainedTrace.sink = nil
        #expect(sunk > 0 && RetainedTrace.linesBuilt > 0, "the instrument sees lines when a sink is installed")
        if let off, let on { #expect(on > off, "a sink costs allocations, off does not: off \(off) on \(on)") }
    }
    #endif
}

#if DEBUG
let debugBuild = true
#else
let debugBuild = false
#endif
