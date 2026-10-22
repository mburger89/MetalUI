import Foundation
#if canImport(Darwin)
import Darwin
#endif
import Testing
import MetalUICore
@testable import MetalUI

// C20, rulings `FI-A`…`FI-K` (`docs/superpowers/2026-10-10-foreach-identity-decisions.md`,
// spec `docs/superpowers/specs/2026-10-10-foreach-identity-design.md` §5): a
// `ForEach` element is identified by its id's Hashable value, not by the id's
// description (divergence 79, retired). SwiftUI's answers are probe arms H1–H3
// of `docs/probes/swiftui-foreach-hashable-identity.swift`.
//
// `Twin`'s description is always "twin", so every pair prints alike and differs
// in value. State is read through `ConditionalCounter` (a count that steps by
// `step` per frame), so a shared entry or a position-bound one reads a
// different number than an own, id-bound one. The `List` residue (`FI-I`,
// divergence 255) was fixed in record §145; `ListRowIdentityTests` holds its pins.

private let size = Size<Pixels>(width: Pixels(200), height: Pixels(100))
private let root = GlobalElementID.child(of: nil, at: 0, name: nil)

struct IdentityTwin: Hashable, CustomStringConvertible {
    let u: Int
    var description: String { "twin" }
}

private typealias Twin = IdentityTwin

/// Renders `make(step)` per step against one table; returns the reads.
@MainActor
private func render<Step>(_ steps: [Step], _ make: (Step, ConditionalReads) -> some Element) -> ConditionalReads {
    let table = StateTable()
    let reads = ConditionalReads()
    for step in steps {
        var tree = make(step, reads)
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }
    return reads
}

private func label(_ t: Twin) -> String { "t\(t.u)" }

/// A `Row` of one counter per twin; step 10^(u-1) so the counts tell the twins apart.
@MainActor
private func twinRow(_ twins: [Twin], _ reads: ConditionalReads) -> some Element {
    Row {
        ForEach(twins, id: \.self) { t in
            ConditionalCounter(label(t), reads, step: t.u == 1 ? 1 : 10)
        }
    }
}

/// **2.1 — ids equal in description and unequal in value keep separate
/// `@State`** (probe H1). Twin(1) steps 1, Twin(2) steps 10, three frames: 3 and
/// 30. Red before: Twin(2) never read.
/// Mutation **M1** (plain names) reddens it.
@MainActor
@Test func idsEqualInDescriptionButNotInValueKeepSeparateState() {
    let reads = render([0, 1, 2]) { _, reads in twinRow([Twin(u: 1), Twin(u: 2)], reads) }
    #expect(reads.values["t1"] == 3 && reads.values["t2"] == 30, "\(reads.values)")
}

/// **2.2 — each twin's state follows its id through a reorder** (probe H2, the
/// separating arm). [1,2] then [2,1]: Twin(1) reads 2, Twin(2) reads 20; state
/// bound to the position would read Twin(2) = 1 + 10 = 11.
/// Mutations **M1**, **M2** (the key built from the index) redden it.
@MainActor
@Test func eachTwinsStateFollowsItsIDThroughAReorder() {
    let reads = render([[1, 2], [2, 1]]) { us, reads in twinRow(us.map { Twin(u: $0) }, reads) }
    #expect(reads.values["t1"] == 2 && reads.values["t2"] == 20, "\(reads.values)")
}

/// **2.3 — equal values are still one element** (probe H3, F7): the value
/// dedupe stays. Two Twin(1): the Row and one element. Mutation **M3**
/// (`Set<ID>` removed) reddens this and 1.8.
@MainActor
@Test func equalValuesStillProduceOnlyTheFirst() {
    let reads = ConditionalReads()
    let frame = Frame(contentSize: size, scaleFactor: 1)
    var tree = twinRow([Twin(u: 1), Twin(u: 1), Twin(u: 2)], reads)
    frame.render(&tree)
    #expect(frame.tree.nodeCount == 3, "Row, Twin(1) once, Twin(2): \(frame.tree.nodeCount)")
}

/// The scope an element's content sits under (its parent).
@MainActor private func scope(_ reads: ConditionalReads, _ label: String) -> PathComponent? {
    reads.ids[label]?.parent?.component
}

/// **2.4 — injective id types mint no key: their paths are today's** (`FI-B`).
/// Int, String and UUID scopes equal `.named(ElementID(String(describing: id)))`
/// with `key == nil`; a Twin's carries its value and differs from the plain
/// name. Mutation **M4** (`needsKey` forced true) reddens it.
@MainActor
@Test func fastPathIDsMintNoKey() throws {
    let uuid = UUID()
    let reads = ConditionalReads()
    var tree = Row {
        ForEach([7], id: \.self) { ConditionalCounter("int\($0)", reads) }
        ForEach(["s"], id: \.self) { ConditionalCounter($0, reads) }
        ForEach([uuid], id: \.self) { _ in ConditionalCounter("uuid", reads) }
        ForEach([Twin(u: 1)], id: \.self) { ConditionalCounter(label($0), reads) }
    }
    Frame(contentSize: size, scaleFactor: 1).render(&tree)
    for (l, name) in [("int7", "7"), ("s", "s"), ("uuid", uuid.description)] {
        let component = try #require(scope(reads, l))
        #expect(component == .named(ElementID(name)), "\(l): \(component)")
        guard case .named(let id) = component else { continue }
        #expect(id.key == nil, "\(l) mints no key")
    }
    guard case .named(let twin)? = scope(reads, "t1") else { Issue.record("no twin scope"); return }
    #expect(twin.name == "twin" && twin.key != nil)
    #expect(PathComponent.named(twin) != .named(ElementID("twin")))
    #expect(twin == ElementID(name: "twin", key: IdentityKey(AnyHashable(Twin(u: 1)))))
}

/// **2.5 — identity work is counted, not timed** (`FI-B`, spec §3.6): 500 Int
/// elements read `(500, 0)`, 500 Twins `(500, 500)`, the same on a second warm
/// frame. Mutations **M4** (keyed forced) and **M5** (the counter bumped per
/// hash, not per element) redden it.
@MainActor
@Test func aWarmForEachCountsItsIdentityWorkNotItsTime() {
    func work<T: Hashable>(_ ids: [T]) -> [(Int, Int)] {
        let table = StateTable()
        return (0..<2).map { _ in
            let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
            var tree = Row { ForEach(ids, id: \.self) { _ in ConditionalCounter("x", ConditionalReads()) } }
            frame.render(&tree)
            return frame.forEachIdentityWork
        }
    }
    let ints = work(Array(0..<500))
    let twins = work((0..<500).map { Twin(u: $0) })
    #expect(ints.map(\.0) == [500, 500] && ints.map(\.1) == [0, 0], "\(ints)")
    #expect(twins.map(\.0) == [500, 500] && twins.map(\.1) == [500, 500], "\(twins)")
}

/// **2.6 — `scrollTo` reaches a twin by value** (`DD-K`): with a request pending
/// the typed keys noted are `Twin(1)` and `Twin(2)` on two distinct scopes, and
/// a lookup by `AnyHashable(Twin(2))` finds the second twin's scope. Mutation
/// **M6** (`noteScrollKey` fed the description) reddens it, as does **M1**.
@MainActor
@Test func scrollToReachesATwinByValue() throws {
    let reads = ConditionalReads()
    let frame = Frame(contentSize: size, scaleFactor: 1)
    frame.scrollRequestQueue.enqueue(ScrollRequest(scope: root, key: AnyHashable(Twin(u: 2)), anchor: nil))
    var tree = twinRow([Twin(u: 1), Twin(u: 2)], reads)
    frame.render(&tree)
    let target = frame.scrollKeys.first { $0.value == AnyHashable(Twin(u: 2)) }?.key
    let second = try #require(reads.ids["t2"]?.parent, "the second twin is produced")
    #expect(frame.scrollKeys.count == 2 && target == second, "\(frame.scrollKeys.count)")
}

/// **2.7 — a twin that leaves and returns starts fresh, its sibling keeps its
/// state** (`ID-R`, `DD-C`). [1,2], [1], [1,2]: Twin(2) reads 1 on its return,
/// Twin(1) reads 3. Mutations **M1**, **M7** (`noteNamed` skipped for keyed
/// scopes) redden it.
@MainActor
@Test func aTwinThatLeavesAndReturnsStartsFreshAndItsSiblingKeepsItsState() {
    let reads = render([[1, 2], [1], [1, 2]]) { us, reads in
        Row { ForEach(us.map { Twin(u: $0) }, id: \.self) { ConditionalCounter(label($0), reads) } }
    }
    #expect(reads.values["t1"] == 3 && reads.values["t2"] == 1, "\(reads.values)")
}

/// **2.8 — a keyed `ElementID` is unequal to a plain one and to another key**,
/// and `GlobalElementID` paths differing only in a key are unequal and hash
/// apart, with `==`'s chain walk untouched (`FI-C`). Mutation **M8**
/// (synthesized `==` replaced by name-only) reddens it.
@MainActor
@Test func anElementIDWithAKeyIsNotEqualToAPlainOneOrToAnotherKey() {
    let a = ElementID(name: "twin", key: IdentityKey(AnyHashable(Twin(u: 1))))
    let a2 = ElementID(name: "twin", key: IdentityKey(AnyHashable(Twin(u: 1))))
    let b = ElementID(name: "twin", key: IdentityKey(AnyHashable(Twin(u: 2))))
    #expect(a == a2 && a.hashValue == a2.hashValue)
    #expect(a != b && a != ElementID("twin"))
    let pa = GlobalElementID.child(of: root, at: 0, name: a)
    let pa2 = GlobalElementID.child(of: root, at: 0, name: a2)
    let pb = GlobalElementID.child(of: root, at: 0, name: b)
    #expect(pa == pa2 && pa != pb && pa.hashValue != pb.hashValue)
    #expect(GlobalElementID.child(of: pa, at: 0, name: nil) != GlobalElementID.child(of: pb, at: 0, name: nil))
}

/// **2.10 — retired.** It pinned the `List` residue (divergence 255, `FI-I`) wrong on purpose;
/// `LH-A` fixed it and `ListRowIdentityTests` is its replacement (record 145).

/// **2.11 — a NaN id is still produced once** (`FI-K`): `Double.nan` is unequal
/// to itself so `Set<ID>` never dedupes it; the floating-point name dedupe does.
/// Mutation **M10** (that dedupe removed) reddens it.
@MainActor
@Test func aNaNIDIsStillProducedOnce() {
    let frame = Frame(contentSize: size, scaleFactor: 1)
    var tree = Row { ForEach([Double.nan, Double.nan], id: \.self) { _ in ConditionalCounter("n", ConditionalReads()) } }
    frame.render(&tree)
    #expect(frame.tree.nodeCount == 2, "the Row and one element: \(frame.tree.nodeCount)")
}

/// **2.12 — the carrier's size is measured, not assumed** (`FI-G`): an
/// `ElementID` is a `String` (16) plus one reference (8) = 24 bytes, and a
/// `GlobalElementID` with a keyed component occupies the same malloc bucket as
/// one with a plain name (Darwin). Mutation: `IdentityKey?` replaced by a bare
/// `AnyHashable?` (a struct, 32 bytes) reddens the size arm.
@MainActor
@Test func theKeyedComponentCostsOneReference() {
    #expect(MemoryLayout<ElementID>.size == 24, "ElementID: \(MemoryLayout<ElementID>.size)")
    print("FI-G ElementID size/stride: \(MemoryLayout<ElementID>.size)/\(MemoryLayout<ElementID>.stride), PathComponent size/stride: \(MemoryLayout<PathComponent>.size)/\(MemoryLayout<PathComponent>.stride)")
    #if canImport(Darwin)
    let plain = GlobalElementID.child(of: root, at: 0, name: ElementID("twin"))
    let keyed = GlobalElementID.child(of: root, at: 0,
                                      name: ElementID(name: "twin", key: IdentityKey(AnyHashable(Twin(u: 1)))))
    let a = malloc_size(Unmanaged.passUnretained(plain).toOpaque())
    let b = malloc_size(Unmanaged.passUnretained(keyed).toOpaque())
    print("FI-G GlobalElementID malloc_size plain/keyed: \(a)/\(b)")
    #expect(a == b, "the same malloc bucket: \(a) vs \(b)")
    #endif
}
