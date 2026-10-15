import Foundation
import Observation
import Testing
@testable import MetalUI

// C14-c lane 1 (`EE-A`…`EE-K`, record §120): what one `@Environment` read is, how two readings compare, how a
// custom key stores its reading, and what the retained-subtree fingerprint holds of custom values and provided
// objects. Tests U1–U7 of `docs/superpowers/specs/2026-10-14-environment-epoch-design.md` §4.

private final class PlainBox { var n = 0 }
private struct HoldsClosure { var run: () -> Void }
private struct IsolatedStruct: @MainActor Equatable { var a: Int }
@Observable @MainActor private final class ObservedModel { var n = 0 }

private enum IntKeyU: EnvironmentKey { static let defaultValue = 0 }
private enum IntKeyU2: EnvironmentKey { static let defaultValue = 0 }
private enum ClosureKeyU: EnvironmentKey { static var defaultValue: HoldsClosure { HoldsClosure(run: {}) } }
private enum ClosureKeyU2: EnvironmentKey { static var defaultValue: HoldsClosure { HoldsClosure(run: {}) } }

/// U1 — an Equatable value reads equal only when equal. Mutation: the `.value` arm of `==` answers true.
@MainActor @Test func anEquatableValueReadsEqualOnlyWhenEqual() {
    #expect(EnvironmentReading.of(3) == .of(3))
    #expect(EnvironmentReading.of(3) != .of(4))
    #expect(EnvironmentReading.of(ColorScheme.dark) == .of(ColorScheme.dark))
    #expect(EnvironmentReading.of(ColorScheme.dark) != .of(ColorScheme.light))
    #expect(EnvironmentReading.of(Int?.none) == .of(Int?.none))
    #expect(EnvironmentReading.of(Int?.some(1)) != .of(Int?.none))
    #expect(EnvironmentReading.of(Font?.none) == .of(Font?.none))
    #expect(EnvironmentReading.of(Font?.some(.system(size: 12))) == .of(Font?.some(.system(size: 12))))
    #expect(EnvironmentReading.of(Font?.some(.system(size: 12))) != .of(Font?.some(.system(size: 13))))
    #expect(EnvironmentReading.of(3) != .of("3"), "a type mismatch is unequal, not a trap")
}

/// U2 — a reference value that is not Equatable reads by identity. Mutation: the `.object` arm answers true.
@MainActor @Test func aReferenceValueReadsByIdentity() {
    let a = PlainBox(), b = PlainBox()
    #expect(EnvironmentReading.of(a) == .of(a))
    #expect(EnvironmentReading.of(a) != .of(b), "a new instance of equal content is a change")
    #expect(EnvironmentReading.of(a) != .uncomparable)
    #expect(EnvironmentReading.of(PlainBox?.some(a)) == .of(PlainBox?.some(a)))
    #expect(EnvironmentReading.of(PlainBox?.some(a)) != .of(PlainBox?.some(b)))
    #expect(EnvironmentReading.of(PlainBox?.none) == .of(PlainBox?.none))
    #expect(EnvironmentReading.of(PlainBox?.none) != .of(PlainBox?.some(a)))
}

/// U3 — a function, a struct holding one and an `EnvironmentValues` read uncomparable and equal nothing, not
/// even themselves. Mutation: `.uncomparable` made equal to itself.
@MainActor @Test func aFunctionOrAFunctionHoldingStructReadsUncomparable() {
    let f: () -> Void = {}
    for reading in [EnvironmentReading.of(f), .of(HoldsClosure(run: {})), .of(EnvironmentValues())] {
        #expect(reading != reading, "an uncomparable reading equals nothing, itself included")
        #expect(reading.isUncomparable)
    }
    #expect(!EnvironmentReading.of(3).isUncomparable)
}

/// U4 — a custom key stores its reading at write; the uncomparable count is of keys, not writes. Mutation: the
/// setter never counts.
@MainActor @Test func aCustomKeyWriteStoresItsReadingAndCountsTheUncomparable() {
    var values = EnvironmentValues()
    #expect(values.uncomparableCustomCount == 0)
    values[IntKeyU.self] = 5
    #expect(values.uncomparableCustomCount == 0, "an Int key is comparable")
    values[ClosureKeyU.self] = HoldsClosure(run: {})
    #expect(values.uncomparableCustomCount == 1)
    values[ClosureKeyU2.self] = HoldsClosure(run: {})
    #expect(values.uncomparableCustomCount == 2)
    values[ClosureKeyU.self] = HoldsClosure(run: { })
    #expect(values.uncomparableCustomCount == 2, "overwriting a key is not a second key")
    #expect(values[IntKeyU.self] == 5)
}

/// U5 — an isolated-conformance value (`struct S: @MainActor Equatable`) reads comparable on the main actor,
/// measured at lane 1 step 0 (record §120): the runtime cast succeeds there, and fails off it (then the reading
/// is uncomparable: safe and counted, never a crash). Mutation: the cast through `any Equatable & Sendable`.
@MainActor @Test func anIsolatedConformanceValueReadsAsMeasured() async {
    #expect(EnvironmentReading.of(IsolatedStruct(a: 1)) == .of(IsolatedStruct(a: 1)))
    #expect(EnvironmentReading.of(IsolatedStruct(a: 1)) != .of(IsolatedStruct(a: 2)))
    // Off the main actor the same cast fails: uncomparable, not a trap.
    let offMain = await Task.detached { nonisolatedReading(IsolatedStruct(a: 1)).isUncomparable }.value
    #expect(offMain)
}

private func nonisolatedReading(_ value: IsolatedStruct) -> EnvironmentReading { .of(value) }

/// U6 — two instances provided as one type are two fingerprints (`EE-K`). Mutation: the fingerprint's `objects`
/// back to type ids.
@MainActor @Test func theFingerprintDistinguishesTwoInstancesProvidedAsOneType() {
    let a = ObservedModel(), b = ObservedModel()
    var one = EnvironmentValues(), two = EnvironmentValues(), same = EnvironmentValues()
    one.setObject(a, as: ObservedModel.self)
    two.setObject(b, as: ObservedModel.self)
    same.setObject(a, as: ObservedModel.self)
    #expect(one.retainedFingerprint != two.retainedFingerprint)
    #expect(one.retainedFingerprint == same.retainedFingerprint)
    #expect(one.retainedFingerprint != EnvironmentValues().retainedFingerprint)
}

/// U7 — the fingerprint holds custom values: different Ints differ, equal ones are equal, an unwritten key
/// equals none. Mutation: `custom` dropped from the fingerprint.
@MainActor @Test func theFingerprintDistinguishesCustomValuesAndNotEqualOnes() {
    var a = EnvironmentValues(), b = EnvironmentValues(), c = EnvironmentValues()
    a[IntKeyU.self] = 1
    b[IntKeyU.self] = 2
    c[IntKeyU.self] = 1
    #expect(a.retainedFingerprint != b.retainedFingerprint)
    #expect(a.retainedFingerprint == c.retainedFingerprint)
    #expect(a.retainedFingerprint != EnvironmentValues().retainedFingerprint)
    c[IntKeyU2.self] = 0
    #expect(a.retainedFingerprint != c.retainedFingerprint, "a second key written, even at its default, is a change")
}
