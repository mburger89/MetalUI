import Foundation
import MetalUIScene
import MetalUITesting
@testable import MetalUI
import Testing

// G47 (record 409): the per-cell cost of a translated (scrolled) `.equatable()` occurrence. A translated hit rebases its ledger in
// place (no `PrepaintLedger` per cell per frame), shares one environment fingerprint box between the keys of a frame and of the
// frames after it (no copy of the 36-field fingerprint per key, an identity test where it was a field-by-field compare), and compares
// the ambient without its offset field by field instead of by copy. Counts and values, never time; the oracle is `==`.

private let g47VerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay counts this test pins are not its to read"

/// 1 - the frame that translates the 24 rows of a shifted stack constructs no ledger and no fingerprint box: each ledger is
/// rebased in place (24 rebases, 24 moves) and the environment of the shifted frame is the one the warm frames held. The settle
/// frame after it constructs neither. **Mutation:** `ledger.rebase(to:_:)` in `retainedPrepaintDecisionInner` replaced by
/// `old.prepaint = ledger.rebased(to: key, translation)` (reddens `ledgersMade`: 24).
/// **Mutation:** `canonicalFingerprint` always making a new box (reddens `boxesMade`).
@Test(.enabled(if: !rsVerifying, g47VerifyingNote)) @MainActor
func aTranslatedFrameConstructsNoLedgerAndNoFingerprintBox() async throws {
    let pair = try RPPair(size: sz(320, 400), scale: 2, warm: 4, accessibility: false, graft: false) { side in
        VStack(spacing: 0) { FSShiftSideRoot(side: side, kind: .header) }
    }
    let window = pair.on.window
    let moves = window.testingLedgerMoves
    let made = Window.testingLedgersMade, rebases = Window.testingLedgerRebases, boxes = Window.testingFingerprintBoxesMade
    for side in [pair.onSide, pair.offSide] { side.inputs.offset += 4 }
    await rsSettle()
    pair.redraw()
    #expect(window.testingLedgerMoves - moves == 24, "set up: the shift moved 24 ledgers: \(window.testingLedgerMoves - moves)")
    #expect(Window.testingLedgersMade - made == 0, "no ledger constructed for a translated hit: \(Window.testingLedgersMade - made)")
    #expect(Window.testingLedgerRebases - rebases == 24, "each moved ledger rebased in place: \(Window.testingLedgerRebases - rebases)")
    #expect(Window.testingFingerprintBoxesMade - boxes == 0, "the environment is the warm frames': \(Window.testingFingerprintBoxesMade - boxes)")
    pair.on.resetFrameWork()
    pair.redraw()
    #expect(Window.testingLedgersMade - made == 0 && Window.testingFingerprintBoxesMade - boxes == 0, "the settle frame too")
    try pair.compare("settled")
    #expect(window.testingFingerprintSlots <= ContentMemoStore.fingerprintSlotLimit, "bounded: \(window.testingFingerprintSlots)")
}

private func fingerprint(_ edit: (inout EnvironmentValues) -> Void = { _ in }) -> EnvironmentFingerprint {
    var values = EnvironmentValues()
    edit(&values)
    return values.retainedFingerprint
}

/// 2 - the slots are bounded and exact: an equal fingerprint finds its box, a different one never does, more than the limit evicts
/// the oldest, and a fingerprint that equals nothing is never kept. **Mutation:** the eviction removed (reddens the bound); the
/// value compare in `canonicalFingerprint` replaced by `true` (reddens the "different" arm).
@Test @MainActor func theFingerprintSlotsAreBoundedAndExact() {
    let store = ContentMemoStore()
    let a = store.canonicalFingerprint(fingerprint())
    #expect(store.canonicalFingerprint(fingerprint()).box === a.box, "an equal value is the same box")
    let b = store.canonicalFingerprint(fingerprint { $0.lineLimit = 3 })
    #expect(b.box !== a.box && b.value != a.value, "a different value is another box")
    for n in 0..<40 { _ = store.canonicalFingerprint(fingerprint { $0.lineLimit = 10 + n }) }
    #expect(store.fingerprintSlotCount == ContentMemoStore.fingerprintSlotLimit, "bounded: \(store.fingerprintSlotCount)")
    #expect(store.canonicalFingerprint(fingerprint()).box !== a.box, "the oldest was evicted; an equal value gets a new box")
    var uncomparable = fingerprint()
    uncomparable.custom[ObjectIdentifier(AMEnvBox.self)] = .uncomparable
    let before = store.fingerprintSlotCount
    let first = store.canonicalFingerprint(uncomparable)
    #expect(store.canonicalFingerprint(uncomparable).box !== first.box && store.fingerprintSlotCount == before, "never kept")
}

/// 3 - `SharedFingerprint` equals what the fingerprint equals: the same box is equal (as a copy of one fingerprint was), equal values
/// in two boxes are equal, different values are not, and an uncomparable fingerprint built twice equals nothing (`EE-F`).
/// **Mutation:** the identity path returning `true` for any two boxes (reddens the different-value arm).
@Test @MainActor func aSharedFingerprintEqualsExactlyWhatTheFingerprintEquals() {
    let plain = SharedFingerprint(fingerprint())
    let samePlain = plain
    #expect(plain == samePlain && plain == SharedFingerprint(fingerprint()))
    #expect(plain != SharedFingerprint(fingerprint { $0.isEnabled = false }))
    var one = fingerprint(), two = fingerprint()
    one.custom[ObjectIdentifier(AMEnvBox.self)] = .uncomparable
    two.custom[ObjectIdentifier(AMEnvBox.self)] = .uncomparable
    #expect(one != two && SharedFingerprint(one) != SharedFingerprint(two), "an uncomparable reading equals nothing built twice")
}

/// 4 - `equalsIgnoringOffset` is `==` with the offset set aside: every other stored field of the key separates it alone, and the
/// offset alone does not. The Mirror count makes a new field owe a row. **Mutation:** one field dropped from
/// `equalsIgnoringOffset` (reddens that field's arm).
@Test @MainActor func everyAmbientFieldButTheOffsetSeparates() throws {
    let base = AmbientKey(clip: [0, 0, 10, 10], offset: [1, 2], layerOpacityScale: [1], depths: [0], scopes: [[1, 2]],
                          environment: fingerprint(), snappingTransaction: false, disablesAnimations: false)
    try #require(Mirror(reflecting: base).children.count == 9, "a new AmbientKey field owes a row in equalsIgnoringOffset and here")
    #expect(base.equalsIgnoringOffset(base))
    var moved = base; moved.offset = [9, 9]
    #expect(moved != base && moved.equalsIgnoringOffset(base), "the offset alone is set aside")
    let edits: [(String, (inout AmbientKey) -> Void)] = [
        ("clip", { $0.clip[0] = 5 }), ("layerOpacityScale", { $0.layerOpacityScale = [2] }), ("depths", { $0.depths = [1] }),
        ("scopes", { $0.scopes = [[1, 3]] }), ("environment", { $0.environment = fingerprint { $0.isEnabled = false } }),
        ("snappingTransaction", { $0.snappingTransaction.toggle() }), ("disablesAnimations", { $0.disablesAnimations.toggle() }),
        ("atlasGeneration", { $0.atlasGeneration = 1 }),
    ]
    for (name, edit) in edits {
        var other = base; edit(&other)
        #expect(!other.equalsIgnoringOffset(base) && other != base, "\(name) separates")
        var both = other; both.offset = [9, 9]
        #expect(!both.equalsIgnoringOffset(base), "\(name) separates under a moved offset too")
    }
}
