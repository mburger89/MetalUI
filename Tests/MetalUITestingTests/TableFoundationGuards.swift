@testable import MetalUI
import Foundation
import Testing

// Foundation's sorting types are what `Table` builds on (`TBL-C`): a guard that they exist and behave on every platform CI builds
// (macOS, Linux, Windows). If CI's Linux or Windows build fails on this file, PR B stops: no MetalUI-owned comparator is added.

private struct Named { var name: String }

/// `SortComparator`, `KeyPathComparator`, `SortOrder`, `String.StandardComparator` and `Never: SortComparator` are all available.
/// Mutation (measured red): delete the `order = .reverse` write; the first expectation fails.
@Test func foundationSortTypesAreAvailableOnEveryPlatform() {
    var s = [KeyPathComparator(\Named.name)]
    s[0].order = .reverse
    #expect(s[0].order == .reverse)
    // `localizedStandard` is Darwin's; corelibs Foundation on Linux and Windows has only `lexical` (divergence 1106, `TBL-X`).
    #if canImport(Darwin)
    let c = String.StandardComparator.localizedStandard
    #expect(c.compare("a", "B") == .orderedAscending)
    #else
    #expect(String.StandardComparator.lexical.compare("B", "a") == .orderedAscending)
    #endif
    #expect(String.StandardComparator.tableDefault == String.StandardComparator.tableDefault)
    func takes<S: SortComparator>(_: S.Type) {}
    takes(Never.self)
}
