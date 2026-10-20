import Foundation
import Testing
@testable import MetalUI

// C14-c4 (`FS-H`, record 126): the graft site's custom-key test is the key's, not a conjunct.

private struct HoldsClosureFS { var run: () -> Void }
private enum ClosureKeyFS: EnvironmentKey { static var defaultValue: HoldsClosureFS { HoldsClosureFS(run: {}) } }
private enum IntKeyFS: EnvironmentKey { static let defaultValue = 0 }

@MainActor private func buildKey(_ environment: EnvironmentValues) -> BuildKey {
    BuildKey(environment: environment.retainedFingerprint, scale: 2, contentSize: Size(width: Pixels(100), height: Pixels(100)),
             snapping: false, disablesAnimations: false, stackAxis: nil, collectsAccessibility: true, depths: [])
}

/// A `BuildKey` whose environment holds an uncomparable reading is unequal to a rebuilt copy of itself, so the graft's
/// `graft.key == key` guard refuses it with no `uncomparableCustomCount` conjunct; an Int key equals its rebuilt copy.
/// Mutation: `custom` dropped from `EnvironmentValues.retainedFingerprint` (the closure key then compares equal).
@MainActor @Test func aBuildKeyUnderAnUncomparableReadingEqualsNothing() {
    var closure = EnvironmentValues()
    closure[ClosureKeyFS.self] = HoldsClosureFS(run: {})
    let key = buildKey(closure)
    // (A key is not compared with itself: a `Dictionary` that shares storage with itself answers `==` by identity.)
    #expect(key != buildKey(closure), "an uncomparable reading equals itself in no rebuilt key")
    var int = EnvironmentValues()
    int[IntKeyFS.self] = 3
    #expect(buildKey(int) == buildKey(int), "an equatable reading equals its rebuilt copy")
    #expect(buildKey(int) != buildKey(EnvironmentValues()), "and differs from the default environment")
}
