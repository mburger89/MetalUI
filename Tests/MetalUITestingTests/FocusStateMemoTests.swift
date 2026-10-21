import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// C14-i lane 2 (`RZ-I`, record 133): an `.equatable()` component that declares `@FocusState` is memoized by the slot's
// version, not refused (divergence 346's remainder). Pins F2-F7 of `docs/superpowers/specs/2026-10-21-retained-zoom-design.md`
// 2.3. Every window is paired with a twin of the same tree with the content memo and retention switched off: the twin is the oracle for the
// scene, the accessibility tree and the hitboxes at every step. Counts only (`FrameWork`, a per-name evaluation log).

/// Getter evaluations by component name (a class: a component's `==` compares it by identity).
@MainActor final class FMLog {
    var evaluations: [String: Int] = [:]
    func note(_ name: String) { evaluations[name, default: 0] += 1 }
    func count(_ name: String) -> Int { evaluations[name, default: 0] }
}

/// A Boolean reader: text and a fill that depend on `focused`, and a focusable box bound to it.
struct FMBool: Component, @MainActor Equatable {
    let name: String
    let log: FMLog
    @FocusState var focused: Bool
    var content: some ElementGroup {
        let _ = log.note(name)
        VStack(spacing: 2) {
            Text("\(name) \(focused ? "focused" : "idle")").frame(width: Pixels(90), height: Pixels(14))
            Box().focusable().focused($focused).frame(width: Pixels(40), height: Pixels(12))
                .background(focused ? Color.accent : Color.red)
        }
    }
    static func == (l: FMBool, r: FMBool) -> Bool { l.name == r.name && l.log === r.log }
}

/// A component whose button writes its own focus state (a pending write from input, `IX-J` item 2).
struct FMWriter: Component, @MainActor Equatable {
    let log: FMLog
    @FocusState var focused: Bool
    var content: some ElementGroup {
        let _ = log.note("writer")
        VStack(spacing: 2) {
            Text("writer \(focused ? "focused" : "idle")").frame(width: Pixels(90), height: Pixels(14))
            Box().focusable().focused($focused).frame(width: Pixels(40), height: Pixels(12))
            Button("take focus") { focused = true }.frame(width: Pixels(80), height: Pixels(18))
        }
    }
    static func == (l: FMWriter, r: FMWriter) -> Bool { l.log === r.log }
}

enum FMField: Hashable { case first, second }

/// An optional reader: two bound boxes and the stored value as text.
struct FMEnum: Component, @MainActor Equatable {
    let log: FMLog
    @FocusState var field: FMField?
    var content: some ElementGroup {
        let _ = log.note("enum")
        VStack(spacing: 2) {
            Text("field \(field.map { "\($0)" } ?? "none")").frame(width: Pixels(90), height: Pixels(14))
            Box().focusable().focused($field, equals: .first).frame(width: Pixels(40), height: Pixels(12))
            Box().focusable().focused($field, equals: .second).frame(width: Pixels(40), height: Pixels(12))
        }
    }
    static func == (l: FMEnum, r: FMEnum) -> Bool { l.log === r.log }
}

enum FMArm: String, Sendable, CaseIterable {
    case three   // three Boolean readers A, B, C
    case writer  // a Boolean reader beside a writer
    case enumerated
}

struct FMRoot: Component {
    let log: FMLog
    let arm: FMArm
    var content: some ElementGroup {
        HStack(alignment: .top, spacing: 8) {
            switch arm {
            case .three:
                ForEach(["A", "B", "C"], id: \.self) { name in
                    FMBool(name: name, log: log).equatable()
                }
            case .writer:
                FMBool(name: "A", log: log).equatable()
                FMWriter(log: log).equatable()
            case .enumerated:
                FMEnum(log: log).equatable()
            }
        }
    }
}

/// A retaining window and its twin with the memo and retention off over one arm.
@MainActor final class FMPair {
    let on: TestWindow, off: TestWindow
    let onLog = FMLog(), offLog = FMLog()

    init(_ arm: FMArm, graft: Bool = true, retain: Bool = true) throws {
        let onLog = self.onLog, offLog = self.offLog
        let options = HeadlessPlatformWindow.Options(appearance: .light, scaleFactor: 1, accessibilityClientActive: true)
        on = try TestWindow(size: sz(420, 120), colorScheme: .light, scaleFactor: 1, options: options, textSystem: harnessTextSystem) {
            VStack(spacing: 0) { FMRoot(log: onLog, arm: arm) }
        }
        off = try TestWindow(size: sz(420, 120), colorScheme: .light, scaleFactor: 1, options: options, textSystem: harnessTextSystem) {
            VStack(spacing: 0) { FMRoot(log: offLog, arm: arm) }
        }
        off.window.testingRetainedSubtrees = false
        off.window.testingContentMemos.isEnabled = false   // the oracle evaluates every getter every frame
        on.window.testingRetainedGraft = graft
        on.window.testingRetainedSubtrees = retain
        settle()
    }

    /// Draws until both windows are quiet (a focus write dirties one frame later).
    func settle(_ frames: Int = 4) {
        for w in [on, off] { for _ in 0..<frames { w.window.setNeedsRedraw(); w.tick() } }
    }

    /// Both windows act, then settle; the twin's scene, tree, hitboxes and tab order must equal the retaining window's.
    func act(_ step: String, _ body: (TestWindow) -> Void) throws {
        for w in [on, off] { body(w) }
        settle()
        let differences = try RPSnapshot(on).differences(from: RPSnapshot(off))
        #expect(differences.isEmpty, "after \(step): \(differences)")
    }

    func tab() throws { try act("tab") { $0.typeKey(.tab) } }
}

/// The sum of the frames recorded since the last reset.
@MainActor func fmSum(_ window: TestWindow) -> FrameWork {
    window.frameWork.dropFirst().reduce(window.frameWork.first ?? FrameWork(), +)
}

/// F2 - a `@FocusState` component is skipped while focus is unchanged, and is not a refusal: no frame counts a content
/// refusal, every idle frame skips, no getter runs. Red at 1bdead8d (`contentRefusals` counted every frame).
/// Mutation: restore the `hasFocusState` refusal in `StateBinder.memoShape`.
@Test @MainActor func aFocusStateComponentIsSkippedWhileFocusIsUnchanged() throws {
    let pair = try FMPair(.three)
    pair.on.resetFrameWork(); pair.onLog.evaluations = [:]
    for _ in 0..<4 { pair.on.window.setNeedsRedraw(); pair.on.tick() }
    let sum = fmSum(pair.on)
    // `dropFirst` keeps three of four frames: nine skips (three readers, three frames) at least.
    #expect(sum.contentRefusals == 0, "no refusal: \(sum.contentRefusals)")
    #expect(sum.contentSkips == 9 && sum.contentEvaluations == 0, "skips \(sum.contentSkips) evaluations \(sum.contentEvaluations)")
    #expect(pair.onLog.evaluations.isEmpty, "no getter ran: \(pair.onLog.evaluations)")
}

/// F3 - a focus move re-evaluates exactly the readers whose reading changed. Tab into A (A evaluates once), Tab to B
/// (A and B once more each), Tab to C, Tab out (back to A: the ring wraps). At every step the scene, tree and
/// hitboxes equal the non-memoized twin's, and an untouched reader's getter has not run. Red at 1bdead8d: every reader
/// evaluated every frame. Mutation: leave the focus slots out of the entry's versions (`ContentMemoStore` `stateIDs`).
@Test @MainActor func aFocusMoveReEvaluatesExactlyTheReadersOfTheMovedState() throws {
    let pair = try FMPair(.three)
    let log = pair.onLog
    log.evaluations = [:]
    try pair.tab()
    #expect(log.count("A") == 1 && log.count("B") == 0 && log.count("C") == 0, "into A: \(log.evaluations)")
    _ = try pair.on.element(label: "A focused")
    try pair.tab()
    #expect(log.count("A") == 2 && log.count("B") == 1 && log.count("C") == 0, "A to B: \(log.evaluations)")
    _ = try pair.on.element(label: "B focused")
    try pair.tab()
    #expect(log.count("A") == 2 && log.count("B") == 2 && log.count("C") == 1, "B to C: \(log.evaluations)")
    _ = try pair.on.element(label: "C focused")
    // Idle frames after the moves skip every reader.
    log.evaluations = [:]
    pair.settle()
    #expect(log.evaluations.isEmpty, "idle after the moves: \(log.evaluations)")
}

/// F4 - a pending write from a click reaches a component that was skipped the frame before. The button writes
/// `focused = true`; the box takes focus at the next frame, the reader shows it and equals the twin. Mutation: the
/// pending-write pass not seeing the skipped component's state (`lastFocusStates` missing it): skipping `noteFocusState`
/// would do it, which is where the finding of `RZ-I` is recorded (the bind runs before the memo decides).
@Test @MainActor func aPendingFocusWriteAppliesToAComponentThatWasSkipped() throws {
    let pair = try FMPair(.writer)
    pair.on.resetFrameWork(); pair.onLog.evaluations = [:]
    pair.settle()
    #expect(pair.onLog.evaluations.isEmpty, "both components were skipped before the click: \(pair.onLog.evaluations)")
    for w in [pair.on, pair.off] { try w.click(w.element(label: "take focus")) }
    pair.settle()
    let differences = try RPSnapshot(pair.on).differences(from: RPSnapshot(pair.off))
    #expect(differences.isEmpty, "after the click: \(differences)")
    _ = try pair.on.element(label: "writer focused")
    _ = try pair.off.element(label: "writer focused")
    // The reader beside it was not touched.
    #expect(pair.onLog.count("A") == 0, "the neighbour stays skipped: \(pair.onLog.evaluations)")
}

/// F5 - focus moved by Tab into a bound box inside a skipped component writes its value back: the optional state reads
/// `.first`, then `.second`, then `nil` after the window loses focus, each equal to the twin.
@Test @MainActor func aSkippedFocusStateIsStillReconciled() throws {
    let pair = try FMPair(.enumerated)
    try pair.tab()
    _ = try pair.on.element(label: "field first")
    try pair.tab()
    _ = try pair.on.element(label: "field second")
    for w in [pair.on, pair.off] { w.window.focus(nil) }
    pair.settle()
    _ = try pair.on.element(label: "field none")
    _ = try pair.off.element(label: "field none")
    let differences = try RPSnapshot(pair.on).differences(from: RPSnapshot(pair.off))
    #expect(differences.isEmpty, "after the focus left: \(differences)")
}

/// F6 - the same under a graft: idle frames graft every reader (the `.focusState` journal event keeps the state bound),
/// Tab moves and returns agree with the twin. Mutation: remove the `.focusState` arm of `RetainedGraft.reapply`.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice: the graft counts this test pins are not its to read"))
@MainActor func aGraftedFocusStateComponentReconciles() throws {
    let pair = try FMPair(.three)
    pair.on.resetFrameWork()
    pair.settle()
    #expect(fmSum(pair.on).retainedGrafts > 0, "the idle frames graft: \(fmSum(pair.on).retainedGrafts)")
    try pair.tab()
    _ = try pair.on.element(label: "A focused")
    try pair.tab()
    _ = try pair.on.element(label: "B focused")
    for w in [pair.on, pair.off] { w.window.focus(nil) }
    pair.settle()
    _ = try pair.on.element(label: "A idle"); _ = try pair.on.element(label: "B idle")
    let differences = try RPSnapshot(pair.on).differences(from: RPSnapshot(pair.off))
    #expect(differences.isEmpty, "after the focus left: \(differences)")
}

/// F7 - the paint of a focus-dependent fill is right across focus in and out under paint retention (`retainedHits`
/// across the idle frames; the scene bytes equal the twin's after every move). Mutation: the paint record ignoring
/// the slot's version (dropping `mark` of the focus slot).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the hit counts this test pins are not its to read"))
@MainActor func aFocusReaderUnderRetentionRepaintsWhenFocusLeaves() throws {
    let pair = try FMPair(.three, graft: false)
    pair.on.resetFrameWork()
    pair.settle()
    #expect(fmSum(pair.on).retainedHits > 0, "idle frames replay paint: \(fmSum(pair.on).retainedHits)")
    for step in 0..<4 { try pair.tab(); _ = step }
    for w in [pair.on, pair.off] { w.window.focus(nil) }
    pair.settle()
    let differences = try RPSnapshot(pair.on).differences(from: RPSnapshot(pair.off))
    #expect(differences.isEmpty, "after the focus left: \(differences)")
}
