import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// C14-c lane 2 (`EE-A`…`EE-K`, record §120): `Component.equatable()` over a component that reads `@Environment`,
// through a real `Window`, counted in `FrameWork`. Tests W1–W9 of
// `docs/superpowers/specs/2026-10-14-environment-epoch-design.md` §4. Counts, never time. The components and keys
// here are internal so `EnvironmentEpochRetentionTests.swift` and `RetainedVerifyTests.swift` build on them.

// MARK: Keys, values and readers

/// A function-holding value: uncomparable (`EE-B`), so a reader of it is refused.
struct EEFn { var run: () -> Int }
/// A class that is not Equatable: compared by identity (`EE-B`).
final class EERef: @unchecked Sendable { let n: Int; init(_ n: Int) { self.n = n } }
let eeDefaultRef = EERef(0)

enum EEIntKey: EnvironmentKey { static let defaultValue = 0 }
enum EEFnKey: EnvironmentKey { static var defaultValue: EEFn { EEFn(run: { 0 }) } }
enum EERefKey: EnvironmentKey { static var defaultValue: EERef { eeDefaultRef } }
extension EnvironmentValues {
    var eeInt: Int { get { self[EEIntKey.self] } set { self[EEIntKey.self] = newValue } }
    var eeFn: EEFn { get { self[EEFnKey.self] } set { self[EEFnKey.self] = newValue } }
    var eeRef: EERef { get { self[EERefKey.self] } set { self[EERefKey.self] = newValue } }
}

/// An `@Observable` object a component reads through `@Environment(EEStore.self)`: `a` is read, `b` never is.
@Observable @MainActor final class EEStore {
    var a: Int
    var b = 0
    init(a: Int = 0) { self.a = a }
}

/// Getter evaluations of a test's readers (a class: the component's `==` compares it by identity).
@MainActor final class EELog { var n = 0 }

/// What a reader draws: a label and a background that depends on the value it read, so a stale read is a wrong
/// scene as well as a wrong label (the retention tests compare scenes).
@MainActor @ElementBuilder
func eeCard(_ label: String, dark: Bool) -> some ElementGroup {
    VStack(spacing: 2) {
        Text(label).frame(width: Pixels(70), height: Pixels(14))
        Box().frame(width: Pixels(30), height: Pixels(8)).background(dark ? Color.accent : Color.red)
    }
}

struct EESchemeReader: Component, @MainActor Equatable {
    let log: EELog
    var memo = true
    @Environment(\.colorScheme) var scheme
    var content: some ElementGroup {
        let _ = log.n += 1
        eeCard(scheme == .dark ? "dark" : "light", dark: scheme == .dark)
    }
    static func == (l: EESchemeReader, r: EESchemeReader) -> Bool { l.memo && r.memo && l.log === r.log }
}

struct EEIntReader: Component, @MainActor Equatable {
    let log: EELog
    var memo = true
    @Environment(\.eeInt) var value
    var content: some ElementGroup {
        let _ = log.n += 1
        eeCard("int\(value)", dark: value % 2 == 0)
    }
    static func == (l: EEIntReader, r: EEIntReader) -> Bool { l.memo && r.memo && l.log === r.log }
}

struct EEFnReader: Component, @MainActor Equatable {
    let log: EELog
    @Environment(\.eeFn) var fn
    var content: some ElementGroup {
        let _ = log.n += 1
        eeCard("fn\(fn.run())", dark: true)
    }
    static func == (l: EEFnReader, r: EEFnReader) -> Bool { l.log === r.log }
}

struct EERefReader: Component, @MainActor Equatable {
    let log: EELog
    @Environment(\.eeRef) var ref
    var content: some ElementGroup {
        let _ = log.n += 1
        eeCard("ref\(ref.n)", dark: true)
    }
    static func == (l: EERefReader, r: EERefReader) -> Bool { l.log === r.log }
}

struct EEObjReader: Component, @MainActor Equatable {
    let log: EELog
    var memo = true
    @Environment(EEStore.self) var store
    var content: some ElementGroup {
        let _ = log.n += 1
        eeCard("a\(store.a)", dark: true)
    }
    static func == (l: EEObjReader, r: EEObjReader) -> Bool { l.memo && r.memo && l.log === r.log }
}

struct EEFocusReader: Component, @MainActor Equatable {
    let log: EELog
    @FocusState var focused: Bool
    var content: some ElementGroup {
        let _ = log.n += 1
        eeCard(focused ? "focused" : "plain", dark: true)
    }
    static func == (l: EEFocusReader, r: EEFocusReader) -> Bool { l.log === r.log }
}

/// A component that declares an object it never reads (W9).
struct EEUnreadObject: Component, @MainActor Equatable {
    @Environment(EEStore.self) var store
    var content: some ElementGroup { Text("unread").frame(width: Pixels(60), height: Pixels(14)) }
    static func == (l: EEUnreadObject, r: EEUnreadObject) -> Bool { true }
}

/// The inputs a window's root reads each frame; written from a test, never from a phase.
@MainActor final class EEModel {
    var int = 0
    var fn = 0
    var ref = EERef(0)
    var store = EEStore()
}

@MainActor func eeRedraw(_ window: TestWindow) -> FrameWork {
    window.window.setNeedsRedraw(); window.tick()
    return window.lastFrameWork
}

/// The window's last scene as bytes, for the memo-off differential.
@MainActor func eeSceneBytes(_ window: TestWindow) -> [Data] {
    func bytes<T>(_ array: [T]) -> Data { array.withUnsafeBytes { Data($0) } }
    return [bytes(window.scene.rects), bytes(window.scene.glyphs), bytes(window.scene.images)]
}

/// Lets the observation hop of a platform without a synchronous `onChange` land before the next draw (`HT-I`).
@MainActor func eeSettle() async {
    for _ in 0..<4 { await Task.yield() }
}

// MARK: W1, W2 — a reader of the built-in scheme

/// W1 — an `@Environment(\.colorScheme)` component whose `==` holds is skipped on a parent tick: one skip, no
/// evaluation, no refusal (divergence 346 no longer refuses it). **Red before (6273e3a4):** one refusal, one
/// evaluation. Mutation: `memoShape` refuses on `hasEnvironment` again.
@Test @MainActor func aReaderOfAnUnchangedEnvironmentValueIsSkipped() throws {
    let log = EELog()
    let window = try harnessWindow { VStack(spacing: 0) { EESchemeReader(log: log).equatable() } }
    _ = try window.element(label: "light")
    for _ in 0..<3 { _ = eeRedraw(window) }
    log.n = 0
    let f = eeRedraw(window)
    #expect(f.contentSkips == 1, "skipped: \(f.contentSkips)")
    #expect(f.contentEvaluations == 0 && f.contentRefusals == 0, "evaluations \(f.contentEvaluations), refusals \(f.contentRefusals)")
    #expect(log.n == 0, "the getter did not run")
}

/// W2 — the scheme changes: the reader is evaluated once, the new value shows (label and scene), and a memo-off twin
/// draws the same scene. Mutation: `entry.readings == readings` replaced by `true` (the label stays `light`).
@Test @MainActor func aReaderIsEvaluatedAgainWhenTheValueItReadChanges() throws {
    func make(memo: Bool) throws -> (TestWindow, EELog) {
        let log = EELog()
        return (try harnessWindow { VStack(spacing: 0) { EESchemeReader(log: log, memo: memo).equatable() } }, log)
    }
    let (window, log) = try make(memo: true)
    let (twin, _) = try make(memo: false)
    for _ in 0..<3 { _ = eeRedraw(window); _ = eeRedraw(twin) }
    log.n = 0
    window.setAppearance(.dark); twin.setAppearance(.dark)
    let f = window.lastFrameWork
    #expect(f.contentEvaluations == 1 && f.contentSkips == 0 && f.contentRefusals == 0,
            "evaluated once: \(f.contentEvaluations)/\(f.contentSkips)/\(f.contentRefusals)")
    #expect(log.n == 1)
    _ = try window.element(label: "dark")
    #expect(throws: (any Error).self) { _ = try window.element(label: "light") }
    #expect(eeSceneBytes(window) == eeSceneBytes(twin), "the memoized frame draws the memo-off frame's scene")
    _ = eeRedraw(window)
    #expect(window.lastFrameWork.contentSkips == 1 && log.n == 1, "skipped again once current")
}

// MARK: W3 — per key read

/// W3 — two readers, one of a custom key and one of the scheme: changing the key evaluates the first only, and
/// flipping the scheme the second only (probe `B1`: per key read). Mutation: compare the whole fingerprint instead of
/// the readings (each change evaluates both).
@Test @MainActor func aReaderOfAnotherKeyIsSkippedWhenAnUnreadKeyChanges() throws {
    let model = EEModel()
    let schemeLog = EELog(), intLog = EELog()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            EESchemeReader(log: schemeLog).equatable()
            EEIntReader(log: intLog).equatable().environment(\.eeInt, model.int)
        }
    }
    for _ in 0..<3 { _ = eeRedraw(window) }
    schemeLog.n = 0; intLog.n = 0
    model.int = 5
    var f = eeRedraw(window)
    #expect(intLog.n == 1 && schemeLog.n == 0, "the key moved: int \(intLog.n), scheme \(schemeLog.n)")
    #expect(f.contentEvaluations == 1 && f.contentSkips == 1 && f.contentRefusals == 0)
    _ = try window.element(label: "int5")
    window.setAppearance(.dark)
    f = window.lastFrameWork
    #expect(schemeLog.n == 1 && intLog.n == 1, "the scheme moved: int \(intLog.n), scheme \(schemeLog.n)")
    #expect(f.contentEvaluations == 1 && f.contentSkips == 1 && f.contentRefusals == 0)
    _ = try window.element(label: "dark")
}

// MARK: W4 — a custom Equatable key

/// W4 — a parent that writes the same Int every tick: skip; a different Int: evaluate; the same again: skip.
/// **Red before:** a refusal every frame. Mutation: the setter stores `.uncomparable` for every value (refusal).
@Test @MainActor func aCustomEquatableKeyRewrittenEqualIsSkipped() throws {
    let model = EEModel()
    let log = EELog()
    let window = try harnessWindow {
        VStack(spacing: 0) { EEIntReader(log: log).equatable().environment(\.eeInt, model.int) }
    }
    for _ in 0..<3 { _ = eeRedraw(window) }
    log.n = 0
    for _ in 0..<3 {
        let f = eeRedraw(window)
        #expect(f.contentSkips == 1 && f.contentEvaluations == 0 && f.contentRefusals == 0, "same Int: skip")
    }
    #expect(log.n == 0)
    model.int = 7
    var f = eeRedraw(window)
    #expect(f.contentEvaluations == 1 && f.contentSkips == 0, "a changed Int: evaluate")
    _ = try window.element(label: "int7")
    f = eeRedraw(window)
    #expect(f.contentSkips == 1 && f.contentEvaluations == 0, "the same Int again: skip")
    #expect(log.n == 1)
}

// MARK: W5 — an uncomparable reading stays refused

/// W5 — a reader of a function-holding key is refused: counted every frame, evaluated every frame, the current value
/// shown (the narrowed divergence 346; replaces the environment half of the old
/// `aComponentWithAnEnvironmentOrFocusStateIsRefusedAndStillEvaluates`). Mutation: `.uncomparable` treated as equal
/// (the shown value goes stale and the refusals read 0).
@Test @MainActor func aReaderOfAFunctionKeyIsRefusedAndStillEvaluates() throws {
    let model = EEModel()
    let log = EELog()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            EEFnReader(log: log).equatable().environment(\.eeFn, EEFn(run: { [model] in model.fn }))
        }
    }
    _ = try window.element(label: "fn0")
    window.resetFrameWork()
    log.n = 0
    let frames = 4
    for _ in 0..<frames { _ = eeRedraw(window) }
    let sum = window.frameWork.dropFirst().reduce(window.frameWork[0], +)
    #expect(sum.contentRefusals == frames, "refused every frame: \(sum.contentRefusals)")
    #expect(sum.contentEvaluations == 0 && sum.contentSkips == 0)
    #expect(log.n == frames, "evaluated every frame: \(log.n)")
    model.fn = 9
    _ = eeRedraw(window)
    _ = try window.element(label: "fn9")
}

// MARK: W6 — a class key by identity

/// W6 — a non-Equatable class value is compared by identity: the same instance skips, a new instance (equal content)
/// evaluates (probe `K2`). Mutation: the `.object` reading compared as always equal (the label stays `ref0`).
@Test @MainActor func aReferenceKeyIsComparedByIdentity() throws {
    let model = EEModel()
    let log = EELog()
    let window = try harnessWindow {
        VStack(spacing: 0) { EERefReader(log: log).equatable().environment(\.eeRef, model.ref) }
    }
    for _ in 0..<3 { _ = eeRedraw(window) }
    log.n = 0
    var f = eeRedraw(window)
    #expect(f.contentSkips == 1 && f.contentEvaluations == 0 && f.contentRefusals == 0, "the same instance: skip")
    model.ref = EERef(1)
    f = eeRedraw(window)
    #expect(f.contentEvaluations == 1 && f.contentSkips == 0, "a new instance: evaluate")
    _ = try window.element(label: "ref1")
    model.ref = EERef(1)    // a new instance again, equal content: still a change
    f = eeRedraw(window)
    #expect(f.contentEvaluations == 1, "a new instance of equal content is a change")
    #expect(log.n == 2)
}

// MARK: W7 — an `@Observable` object

/// W7 — an object reader follows its instance and the properties it read: (a) a parent tick skips, (b) a read property
/// written from input evaluates, (c) an unread property written skips, (d) a swapped provided instance evaluates and
/// shows the new object. (b) and (c) are the observation session's, so exact counts hold where the hop is synchronous
/// and after `eeSettle()` elsewhere. Mutation: the object reading made `.object(nil)` always (reddens d).
@Test @MainActor func anObjectReaderFollowsItsInstanceAndItsReadProperties() async throws {
    let model = EEModel()
    let log = EELog()
    let window = try harnessWindow {
        VStack(spacing: 0) { EEObjReader(log: log).equatable().environment(model.store) }
    }
    _ = try window.element(label: "a0")
    for _ in 0..<3 { _ = eeRedraw(window) }
    log.n = 0
    var f = eeRedraw(window)
    #expect(f.contentSkips == 1 && f.contentEvaluations == 0 && f.contentRefusals == 0, "(a) a tick skips")
    model.store.a = 4
    await eeSettle()
    f = eeRedraw(window)
    #expect(f.contentEvaluations == 1 && f.contentSkips == 0, "(b) a read property evaluates")
    _ = try window.element(label: "a4")
    model.store.b = 9
    await eeSettle()
    f = eeRedraw(window)
    #expect(f.contentSkips == 1 && f.contentEvaluations == 0, "(c) an unread property skips")
    model.store = EEStore(a: 50)
    f = eeRedraw(window)
    #expect(f.contentEvaluations == 1 && f.contentSkips == 0, "(d) a swapped instance evaluates")
    _ = try window.element(label: "a50")
    #expect(log.n == 2, "two evaluations in all, (b) and (d): \(log.n)")
}

// MARK: W8, W9

/// W8 — `@FocusState` stays refused (`EE-E`): counted every frame, evaluated every frame. Mutation: `refused = false`.
@Test @MainActor func aFocusStateComponentStaysRefused() throws {
    let log = EELog()
    let window = try harnessWindow { VStack(spacing: 0) { EEFocusReader(log: log).equatable() } }
    _ = try window.element(label: "plain")
    window.resetFrameWork()
    log.n = 0
    let frames = 4
    for _ in 0..<frames { _ = eeRedraw(window) }
    let sum = window.frameWork.dropFirst().reduce(window.frameWork[0], +)
    #expect(sum.contentRefusals == frames, "refused every frame: \(sum.contentRefusals)")
    #expect(sum.contentEvaluations == 0 && sum.contentSkips == 0)
    #expect(log.n == frames)
}

/// W9 — a declared, unprovided, never-read `@Environment(Model.self)` does not trap in the probe (`EE-D`): the child
/// builds and redraws such a window and exits normally. Mutation: the probe reads through the trapping `read` — the
/// child traps with the missing-object message and the exit test reddens.
@Test @MainActor func aDeclaredButUnreadMissingObjectDoesNotTrapInTheProbe() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            guard let window = try? TestWindow(size: sz(200, 80), textSystem: harnessTextSystem, content: {
                VStack(spacing: 0) { EEUnreadObject().equatable() }
            }) else { exit(2) }
            for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
        }
    }
}
