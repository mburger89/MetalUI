import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// C14-c lane 2 (`EE-F`, `EE-K`, record §120): retained subtrees (`SB-`, `RK-`) over components that read
// `@Environment`. Tests R1–R6 of `docs/superpowers/specs/2026-10-14-environment-epoch-design.md` §4. Every window
// is a pair (`RPPair`): one retaining, one not, compared after each step. Counts, never time. Under
// `METALUI_VERIFY_RETAINED=1` the count assertions are off (`rsVerifying`: a hit is painted as a miss) and the
// differentials stay; `RetainedVerifyTests` runs scenarios R1 and R3 in a verify-mode child.

private let verifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay and graft counts this test pins are not its to read"

/// A frame's replay and content counters, for failure messages.
func eeCounters(_ f: FrameWork) -> String {
    "hits \(f.retainedHits) misses \(f.retainedMisses) ineligible \(f.retainedIneligible) prepaintHits \(f.retainedPrepaintHits) prepaintIneligible \(f.retainedPrepaintIneligible) grafts \(f.retainedGrafts) graftIneligible \(f.retainedGraftIneligible) redos \(f.retainedRedos) | evaluations \(f.contentEvaluations) skips \(f.contentSkips) refusals \(f.contentRefusals)"
}

/// What each side of a pair holds: one log, one provided store and one class value, written by the test.
@MainActor final class EESide {
    let log = EELog()
    /// A second log, for a sibling reader.
    let log2 = EELog()
    var store = EEStore()
    var ref = EERef(0)
}

/// The two sides of a pair by their `RPSide`, made on first use (the root closure runs every frame).
@MainActor final class EESides {
    private var sides: [ObjectIdentifier: EESide] = [:]
    func of(_ side: RPSide) -> EESide {
        if let existing = sides[ObjectIdentifier(side)] { return existing }
        let made = EESide(); sides[ObjectIdentifier(side)] = made; return made
    }
}

/// The scenarios the verify-mode child also runs (`RetainedVerifyTests`).
enum EEScenario: String, CaseIterable {
    /// R1: a reader of the scheme, the scheme flips.
    case schemeFlip
    /// R3: a reader of the scheme under a custom key it does not read, the key changes.
    case unreadKey
    /// R1b: a reader of a custom key (not the scheme) that paints a token colour, the scheme flips.
    case unreadScheme
}

/// The root of a scenario's pair.
@MainActor
func eeRoot(_ scenario: EEScenario, _ sides: EESides, _ side: RPSide) -> some Element {
    VStack(spacing: 4) { eeUnit(scenario, sides.of(side).log, side.model.n) }
}

@MainActor @ElementBuilder
private func eeUnit(_ scenario: EEScenario, _ log: EELog, _ n: Int) -> some ElementGroup {
    switch scenario {
    case .schemeFlip: EESchemeReader(log: log).equatable()
    case .unreadKey: EESchemeReader(log: log).equatable().environment(\.eeInt, n)
    case .unreadScheme: EEIntReader(log: log).equatable()
    }
}

/// Draws a scenario's steps on a pair; the steps are the ones the tests below pin, so a child process under
/// verify mode draws exactly them.
@MainActor func eeDrawScenario(_ scenario: EEScenario) throws {
    let sides = EESides()
    let pair = try RPPair(size: sz(200, 80), warm: 4) { eeRoot(scenario, sides, $0) }
    for _ in 0..<2 { pair.redraw() }
    switch scenario {
    case .schemeFlip, .unreadScheme:
        pair.on.setAppearance(.dark); pair.off.setAppearance(.dark)
    case .unreadKey:
        pair.onSide.model.n = 3; pair.offSide.model.n = 3
        pair.redraw()
    }
    for _ in 0..<3 { pair.redraw() }
    try pair.compare("\(scenario)")
}

// MARK: R1 — a replay misses when a value the occurrence read changes

/// R1 — a retained reader of `@Environment(\.colorScheme)`: it replays while the scheme holds; in the frame the scheme
/// flips the getter is evaluated (an evaluated occurrence is counted ineligible, never a hit); in the next frame the
/// getter is skipped but the **record misses** (its fingerprint holds the old scheme) and the scene is the
/// retention-off window's; then the new record replays. **Red before (6273e3a4):** the refused reader has no entry, so
/// it never replays at all (`retainedHits` 0 in the steady frame). Mutation: `colorScheme` dropped from
/// `retainedFingerprint` (the frame after the flip hits the old record).
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aReplayMissesWhenAnEnvironmentValueItReadChanges() throws {
    let sides = EESides()
    let pair = try RPPair(size: sz(200, 80), warm: 4) { eeRoot(.schemeFlip, sides, $0) }
    try pair.compare("warm")
    pair.redraw()
    var f = try #require(pair.frames.last)
    #expect(f.retainedHits == 1 && f.retainedMisses == 0 && f.retainedIneligible == 0, "steady: \(eeCounters(f))")
    #expect(f.contentSkips == 1 && f.contentRefusals == 0)
    pair.on.setAppearance(.dark); pair.off.setAppearance(.dark)
    f = pair.on.lastFrameWork
    #expect(f.retainedHits == 0 && f.contentEvaluations == 1, "the flip frame evaluates and replays nothing: \(eeCounters(f))")
    _ = try pair.on.element(label: "dark")
    try pair.compare("the flip")
    pair.redraw()
    f = try #require(pair.frames.last)
    #expect(f.retainedHits == 0 && f.retainedMisses == 1, "the record under the old scheme misses: \(eeCounters(f))")
    #expect(f.contentSkips == 1 && f.contentEvaluations == 0, "while the getter is skipped: \(eeCounters(f))")
    try pair.compare("the miss")
    pair.redraw()
    f = try #require(pair.frames.last)
    #expect(f.retainedHits == 1 && f.retainedMisses == 0, "the new record replays: \(eeCounters(f))")
    try pair.compare("the new record")
}

/// R1b — a retained reader of another key (its background is the `.accent` token, resolved through the scheme's theme at
/// paint): the scheme flips, its getter is **skipped** (it did not read the scheme), and the replay **misses**, because
/// the fingerprint holds the scheme; the scene is the retention-off window's. This is the pin the fingerprint's
/// `colorScheme` field needs (R1 alone survives its removal: an evaluated reader re-records anyway). Mutation:
/// `colorScheme` dropped from `retainedFingerprint` (a stale record replays: hits 1, scene differs).
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aReplayMissesWhenTheSchemeFlipsUnderAReaderOfAnotherKey() throws {
    let sides = EESides()
    let pair = try RPPair(size: sz(200, 80), warm: 4) { eeRoot(.unreadScheme, sides, $0) }
    try pair.compare("warm")
    pair.redraw()
    try #require(pair.frames.last?.retainedHits == 1, "replays while the scheme holds")
    pair.on.setAppearance(.dark); pair.off.setAppearance(.dark)
    let f = pair.on.lastFrameWork
    #expect(f.contentSkips == 1 && f.contentEvaluations == 0, "the getter is skipped: \(eeCounters(f))")
    #expect(f.retainedHits == 0 && f.retainedMisses == 1, "the replay misses: \(eeCounters(f))")
    try pair.compare("the flip")
}

// MARK: R2 — a replay hits when a scope not on its path changes

/// R2 — a sibling's `.environment(\.eeInt, …)` changes: the scheme reader, outside that scope, still hits (and skips its
/// getter); the sibling's getter runs (an evaluated occurrence is counted ineligible). Mutation: the fingerprint built from the root environment instead of the
/// position's (the sibling's key reaches the reader's key: a miss).
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aReplayHitsWhenAScopeNotOnItsPathChanges() throws {
    let sides = EESides()
    let pair = try RPPair(size: sz(200, 140), warm: 4) { side in
        let mine = sides.of(side)
        return VStack(spacing: 4) {
            EESchemeReader(log: mine.log).equatable()
            EEIntReader(log: mine.log2).equatable().environment(\.eeInt, side.model.n)
        }
    }
    try pair.compare("warm")
    pair.redraw()
    try #require(pair.frames.last?.retainedHits == 2, "both replay while nothing moves")
    pair.onSide.model.n = 3; pair.offSide.model.n = 3
    pair.redraw()
    let f = try #require(pair.frames.last)
    #expect(f.retainedHits == 1, "the reader hits: \(eeCounters(f))")
    #expect(f.retainedMisses == 0 && f.retainedIneligible == 1, "the sibling was evaluated, so it is ineligible this frame: \(eeCounters(f))")
    #expect(f.contentSkips == 1 && f.contentEvaluations == 1, "the reader's getter is skipped, the sibling's runs: \(eeCounters(f))")
    try pair.compare("the sibling's key")
}

// MARK: R3 — an unread value at the position skips the getter and misses the replay

/// R3 (`EE-F`, the honest pin) — a custom key the reader does not read changes **at its position**: the getter is
/// skipped (its readings are equal) while the retained record misses (the replay key is the whole position's
/// fingerprint, carried as C14-c3). The scene is the retention-off window's. Mutation: `custom` dropped from the
/// fingerprint (the record hits: here the scene is the same, so the miss count reddens it).
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func anUnreadValueAtItsPositionSkipsTheGetterButMissesTheReplay() async throws {
    let sides = EESides()
    let pair = try RPPair(size: sz(200, 80), warm: 4) { eeRoot(.unreadKey, sides, $0) }
    try pair.compare("warm")
    pair.redraw()
    try #require(pair.frames.last?.retainedHits == 1)
    pair.onSide.model.n = 3; pair.offSide.model.n = 3
    pair.redraw()
    let f = try #require(pair.frames.last)
    #expect(f.contentSkips == 1 && f.contentEvaluations == 0 && f.contentRefusals == 0, "the getter is skipped: \(f.contentSkips)/\(f.contentEvaluations)")
    #expect(f.retainedMisses == 1 && f.retainedHits == 0, "the replay misses: \(f.retainedHits)/\(f.retainedMisses)")
    try pair.compare("the unread key")
}

// MARK: R4 — which custom keys keep an occurrence ineligible

/// R4 — an Equatable custom key (an Int) no longer makes an occurrence ineligible: the reader under it replays.
/// **Red before:** `retainedIneligible` 1, `customEnvironmentKey`. Mutation: each of the three `uncomparableCustomCount`
/// sites restored to `customKeyCount` (`retainedEntryRefusal`, the prepaint refusal, the graft guard), one run each.
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func anEquatableCustomKeyNoLongerMakesAnOccurrenceIneligible() throws {
    let sides = EESides()
    let pair = try RPPair(size: sz(200, 80), warm: 5) { side in
        VStack(spacing: 4) { EESchemeReader(log: sides.of(side).log).equatable().environment(\.eeInt, 3) }
    }
    pair.redraw()
    let f = try #require(pair.frames.last)
    #expect(f.retainedHits == 1 && f.retainedIneligible == 0, "replays: \(f.retainedHits)/\(f.retainedIneligible)")
    #expect(f.retainedPrepaintIneligible == 0 && f.retainedGraftIneligible == 0, "prepaint \(f.retainedPrepaintIneligible), graft \(f.retainedGraftIneligible)")
    #expect(f.retainedGrafts == 1, "and grafts: \(f.retainedGrafts)")
    try pair.compare("an Int key")
}

/// R4b — a function-holding custom key still does: ineligible at the paint record and at the prepaint, and no graft (the
/// graft guard declines without a counter). The two counted sites are pinned here; the graft site is pinned by R4 (its
/// guard restored to counting every key refuses the Int key). Mutation: the paint-record site made `> 99`
/// (`retainedIneligible` 0), the prepaint site likewise (`retainedPrepaintIneligible` 0).
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func anUncomparableCustomKeyStillDoes() throws {
    let sides = EESides()
    let pair = try RPPair(size: sz(200, 80), warm: 5) { side in
        VStack(spacing: 4) {
            EESchemeReader(log: sides.of(side).log).equatable().environment(\.eeFn, EEFn(run: { 3 }))
        }
    }
    pair.redraw()
    let f = try #require(pair.frames.last)
    #expect(f.retainedHits == 0 && f.retainedIneligible == 1, "ineligible: \(f.retainedHits)/\(f.retainedIneligible)")
    #expect(f.retainedPrepaintIneligible >= 1, "prepaint: \(f.retainedPrepaintIneligible)")
    #expect(f.retainedGrafts == 0, "no graft: \(eeCounters(f))")
    try pair.compare("a function key")
}

// MARK: R5 — a graft misses when a custom key changes

/// R5 — the graft's `BuildKey` carries the fingerprint: while a reader's position holds an Int key it grafts; the key
/// changes (the reader does not read it) and the graft misses (the build runs, the getter is skipped), the scene equals
/// the retention-off window's. Mutation: the graft's key built without `custom`.
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aGraftMissesWhenACustomKeyChanges() throws {
    let sides = EESides()
    let pair = try RPPair(size: sz(200, 80), warm: 5) { eeRoot(.unreadKey, sides, $0) }
    pair.redraw()
    try #require(pair.frames.last?.retainedGrafts == 1, "grafts while the key holds")
    pair.onSide.model.n = 3; pair.offSide.model.n = 3
    pair.redraw()
    var f = try #require(pair.frames.last)
    #expect(f.retainedGrafts == 0, "the changed key misses the graft: \(eeCounters(f))")
    #expect(f.contentSkips == 1 && f.contentEvaluations == 0)
    try pair.compare("the graft's miss")
    pair.redraw(); pair.redraw()   // the miss records the build again; the frame after grafts on the new key
    f = try #require(pair.frames.last)
    #expect(f.retainedGrafts == 1, "and grafts again on the new key: \(eeCounters(f))")
}

// MARK: R6 — a swapped object misses a replay and a graft

/// R6 (`EE-K`) — a provided `@Observable` object swapped for another **instance of the same type**: a reader of the
/// scheme (which does not declare it) skips its getter but misses the replay and the graft (the fingerprint holds the
/// instance); a reader of the object evaluates and draws the new object's value. Scenes equal the retention-off
/// window's. Mutation: `objects` back to type ids (the first reader replays the old record).
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func anObjectSwapMissesAReplayAndAGraft() throws {
    let sides = EESides()
    let pair = try RPPair(size: sz(200, 140), warm: 5) { side in
        let mine = sides.of(side)
        return VStack(spacing: 4) {
            EESchemeReader(log: mine.log).equatable().environment(mine.store)
            EEObjReader(log: mine.log2).equatable().environment(mine.store)
        }
    }
    try pair.compare("warm")
    pair.redraw()
    var f = try #require(pair.frames.last)
    try #require(f.retainedHits == 2 && f.retainedGrafts == 2, "both replay and graft while nothing moves: \(f.retainedHits)/\(f.retainedGrafts)")
    for side in [sides.of(pair.onSide), sides.of(pair.offSide)] { side.store = EEStore(a: 8) }
    pair.redraw()
    f = try #require(pair.frames.last)
    #expect(f.retainedHits == 0 && f.retainedMisses == 2, "both miss: \(f.retainedHits)/\(f.retainedMisses)")
    #expect(f.retainedGrafts == 0, "no graft: \(f.retainedGrafts)")
    #expect(f.contentSkips == 1 && f.contentEvaluations == 1, "the scheme reader skips, the object reader evaluates: \(f.contentSkips)/\(f.contentEvaluations)")
    _ = try pair.on.element(label: "a8")
    try pair.compare("the swap")
}
