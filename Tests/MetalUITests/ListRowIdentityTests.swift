import Foundation
import Testing
import MetalUICore
@testable import MetalUI

// Round 2 item 8, rulings `LH-A`...`LH-I`
// (`docs/superpowers/2026-10-22-list-row-identity-decisions.md`): a `List` row is
// identified by its id's Hashable value, as a `ForEach` element is (`FI-A`), so
// divergence 255 is retired. SwiftUI's answers are probe arms L1-L3 of
// `docs/probes/swiftui-list-row-identity.swift`. `IdentityTwin`'s description is
// always "twin", so every pair prints alike and differs in value.
//
// **Red before** (record 145): tests 1, 2, 3, 5, 6 and 9 failed on the unchanged `List`
// (shared state, last write wins, a counter never bumped); 4, 7 and 8 are
// characterizations that held before and after.

private let size = Size<Pixels>(width: Pixels(200), height: Pixels(200))
private let root = GlobalElementID.child(of: nil, at: 0, name: nil)
private typealias Twin = IdentityTwin

private struct TwinItem: Identifiable { let id: Twin }
private struct IntItem: Identifiable { let id: Int }
private struct StringItem: Identifiable { let id: String }
private struct UUIDItem: Identifiable { let id: UUID }

private func label(_ t: Twin) -> String { "t\(t.u)" }
private func step(_ t: Twin) -> Int { t.u == 1 ? 1 : 10 }

private enum Path { case uniform, variable }

/// A `List` of one counter per twin, in the given sizing form.
@MainActor
private func twinList(_ path: Path, _ us: [Int], _ reads: ConditionalReads) -> some Element {
    let items = us.map { TwinItem(id: Twin(u: $0)) }
    return Row {
        if path == .uniform {
            List(items, rowHeight: Pixels(20)) { item in
                ConditionalCounter(label(item.id), reads, step: step(item.id))
            }
        } else {
            List(items) { item in
                ConditionalCounter(label(item.id), reads, step: step(item.id))
            }
        }
    }
}

@MainActor
private func render(_ path: Path, _ steps: [[Int]], reads: ConditionalReads = ConditionalReads(),
                    table: StateTable = StateTable()) -> ConditionalReads {
    for us in steps {
        var tree = twinList(path, us, reads)
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }
    return reads
}

/// **1 (probe L1).** Twin(1) steps 1, Twin(2) steps 10, three frames: 3 and 30.
/// Red before: Twin(2) shared Twin(1)'s entry. Mutation **M1**.
@MainActor
@Test func aUniformListsCollidingIDsKeepSeparateState() {
    let reads = render(.uniform, [[1, 2], [1, 2], [1, 2]])
    #expect(reads.values["t1"] == 3 && reads.values["t2"] == 30, "\(reads.values)")
}

/// **2 (probe L1), the variable-height path.** Mutations **M1**, **M1b**.
@MainActor
@Test func aVariableListsCollidingIDsKeepSeparateState() {
    let reads = render(.variable, [[1, 2], [1, 2], [1, 2]])
    #expect(reads.values["t1"] == 3 && reads.values["t2"] == 30, "\(reads.values)")
}

/// **3 (probe L2, the separating arm).** [1,2] then [2,1]: Twin(1) reads 2, Twin(2) reads 20; state
/// bound to the position would read 11 for Twin(2). Both paths. Mutation **M1**.
@MainActor
@Test(arguments: [Path.uniform, Path.variable])
private func aListRowsStateFollowsItsIDThroughAReorder(_ path: Path) {
    let reads = render(path, [[1, 2], [2, 1]])
    #expect(reads.values["t1"] == 2 && reads.values["t2"] == 20, "\(path): \(reads.values)")
}

/// **4, a characterization (green before).** An injective id names its row
/// `ElementID(String(describing:))` with no key and mints no `IdentityKey` (`LH-C`).
/// Mutation **M2** (`keyed` forced true).
@MainActor
@Test func anInjectiveListRowNamesThePlainIDByteForByte() throws {
    func names<I: Identifiable>(_ items: [I], _ path: Path) throws -> ([ElementID], (rows: Int, keyed: Int))
    where I.ID: Hashable {
        let reads = ConditionalReads()
        let frame = Frame(contentSize: size, scaleFactor: 1)
        var tree = Row {
            if path == .uniform {
                List(items, rowHeight: Pixels(20)) { ConditionalCounter(String(describing: $0.id), reads) }
            } else {
                List(items) { ConditionalCounter(String(describing: $0.id), reads) }
            }
        }
        frame.render(&tree)
        var out: [ElementID] = []
        for item in items {
            let row = try #require(reads.ids[String(describing: item.id)]?.parent, "row produced")
            guard case .named(let name) = row.component else { Issue.record("not named"); continue }
            out.append(name)
        }
        return (out, frame.listIdentityWork)
    }
    let uuids = [UUID(), UUID()]
    for path in [Path.uniform, .variable] {
        let (ints, intWork) = try names((0..<3).map { IntItem(id: $0) }, path)
        #expect(ints == (0..<3).map { ElementID(String($0)) } && ints.allSatisfy { $0.key == nil })
        let (strings, _) = try names(["a", "b"].map { StringItem(id: $0) }, path)
        #expect(strings == [ElementID("a"), ElementID("b")] && strings.allSatisfy { $0.key == nil })
        let (ids, uuidWork) = try names(uuids.map { UUIDItem(id: $0) }, path)
        #expect(ids == uuids.map { ElementID($0.description) } && ids.allSatisfy { $0.key == nil })
        #expect(intWork.keyed == 0 && uuidWork.keyed == 0 && intWork.rows == 3 && uuidWork.rows == 2,
                "\(path): \(intWork) \(uuidWork)")
    }
}

/// **5 (`LH-D` site 3).** An accessibility selection request naming Twin(2)'s row selects Twin(2):
/// `byRow` was one entry per description, the last write winning. Red before. Mutation **M3**.
@MainActor
@Test func anAccessibilitySelectionPicksTheRightRowAmongCollidingIDs() {
    let items = [1, 2, 3].map { TwinItem(id: Twin(u: $0)) }
    let list = GlobalElementID.child(of: root, at: 0, name: nil)
    func rowID(_ t: Twin) -> GlobalElementID {
        GlobalElementID.child(of: list, at: 0,
                              name: ElementID(name: "twin", key: IdentityKey(AnyHashable(t))))
    }
    var picked: Twin?
    let binding = Binding<Twin?>(get: { picked }, set: { picked = $0 })
    let table = StateTable()
    let handler = List<[TwinItem], ConditionalCounter>.accessibilityRowSelection(
        list: list, data: items, selection: .single(binding), table: table)
    handler(AccessibilityRowSelection(rows: [rowID(Twin(u: 2))]))
    #expect(picked == Twin(u: 2), "\(String(describing: picked))")
    handler(AccessibilityRowSelection(rows: [rowID(Twin(u: 1))]))
    #expect(picked == Twin(u: 1), "\(String(describing: picked))")
}

/// **6 (`LH-D` site 2, `DD-K`).** A pending `scrollTo(Twin(2))` notes Twin(2)'s own row scope, in
/// both paths. Red before: the note named the plain description, so no row matched. Mutation **M4**.
@MainActor
@Test(arguments: [Path.uniform, Path.variable])
private func aPendingScrollToReachesTheRightRowAmongCollidingIDs(_ path: Path) throws {
    let reads = ConditionalReads()
    let frame = Frame(contentSize: size, scaleFactor: 1)
    frame.scrollRequestQueue.enqueue(ScrollRequest(scope: root, key: AnyHashable(Twin(u: 2)), anchor: nil))
    var tree = twinList(path, [1, 2], reads)
    frame.render(&tree)
    let target = frame.scrollKeys.first { $0.value == AnyHashable(Twin(u: 2)) }?.key
    let second = try #require(reads.ids["t2"]?.parent, "the second twin's row is produced")
    #expect(frame.scrollKeys.count == 2 && target == second, "\(path): \(frame.scrollKeys.count)")
}

/// **7, a characterization of `TB-AH` under keys (`LH-H`).** Twin rows past 256 table entries: a row out
/// of the window for a 2-generation excursion keeps its state, one left for 3 loses it. Mutation **M5**
/// (site 1 plain) shares one scope across the twins, so each assertion reddens.
@MainActor
@Test func aKeyedListRowsStateSurvivesABoundedExcursionButNotALongerOne() throws {
    let items = (0..<12).map { TwinItem(id: Twin(u: $0)) }
    let reads = ConditionalReads()
    let table = StateTable()
    let padding = (0..<260).map { GlobalElementID.child(of: nil, at: 10_000 + $0, name: ElementID("pad\($0)")) }
    for id in padding { table.write(id, 0) }
    var tree = ScrollView(.vertical, elementID: ElementID("scroller")) {
        List(items, rowHeight: Pixels(20)) { item in ConditionalCounter(label(item.id), reads) }
    }
    let scrollerID = GlobalElementID.child(of: nil, at: 0, name: ElementID("scroller"))
    let contentSize = Size<Pixels>(width: Pixels(100), height: Pixels(20))
    func renderFrame(offset: Double?) {
        for id in padding { table.mark(id) }
        if let offset {
            let current = table.peek(scrollerID, as: ScrollState.self) ?? ScrollState()
            table.write(scrollerID, ScrollState(offset: offset, lastScrollTime: current.lastScrollTime,
                                                viewportExtent: current.viewportExtent))
        }
        Frame(contentSize: contentSize, scaleFactor: 1, stateTable: table).render(&tree)
    }
    renderFrame(offset: nil)
    renderFrame(offset: 100)
    renderFrame(offset: 100)
    // Rows 4 and 7 are in [3, 8): three productions each.
    #expect(reads.values["t4"] == 3 && reads.values["t7"] == 3, "\(reads.values)")
    renderFrame(offset: 0)   // window [0, 3): both leave
    renderFrame(offset: 0)
    renderFrame(offset: 100)  // 4 returns after two generations
    #expect(reads.values["t4"] == 4, "the bounded excursion keeps the state: \(reads.values)")
    renderFrame(offset: 100)
    renderFrame(offset: 100)
    // Row 7 was kept alive by the window [3, 8) above; leave for three generations.
    renderFrame(offset: 0)
    renderFrame(offset: 0)
    renderFrame(offset: 0)
    renderFrame(offset: 100)
    #expect(reads.values["t7"] == 1, "a longer one loses it: \(reads.values)")
}

/// **8.** The same id through `ForEach`, `List` and a `LazyVStack` unit names one `ElementID`.
/// Mutation **M6** (a prefix in the row's name).
@MainActor
@Test func aListRowAndAForEachElementNameTheSameID() throws {
    func name(_ reads: ConditionalReads, _ key: String) throws -> ElementID {
        let scope = try #require(reads.ids[key]?.parent, "\(key) produced")
        guard case .named(let n) = scope.component else { throw NSError(domain: "not named", code: 1) }
        return n
    }
    let a = ConditionalReads(), b = ConditionalReads(), c = ConditionalReads()
    var forEach = Row { ForEach([Twin(u: 7)], id: \.self) { ConditionalCounter(label($0), a) } }
    Frame(contentSize: size, scaleFactor: 1).render(&forEach)
    var list = twinList(.uniform, [7], b)
    Frame(contentSize: size, scaleFactor: 1).render(&list)
    var variable = twinList(.variable, [7], c)
    Frame(contentSize: size, scaleFactor: 1).render(&variable)
    let expected = ElementID(name: "twin", key: IdentityKey(AnyHashable(Twin(u: 7))))
    #expect(try name(a, "t7") == expected)
    #expect(try name(b, "t7") == expected)
    #expect(try name(c, "t7") == expected)
}

/// **9 (`LH-E`).** Identity work is per realised row: `rows == window` and `keyed` is 0 for `Int`, the
/// window for a Twin, at 500 and 5000 rows (and 100k under `METALUI_RUN_100K_LIST_TEST=1`), on a warm
/// second frame too. Mutation **M7** (minting over all of `data`).
@MainActor
@Test func aListsIdentityWorkIsPerRealisedRowAtAnyCount() throws {
    var counts = [500, 5000]
    if ProcessInfo.processInfo.environment["METALUI_RUN_100K_LIST_TEST"] == "1" { counts.append(100_000) }
    func work<I: Identifiable>(_ items: [I], _ path: Path) -> [(rows: Int, keyed: Int)] where I.ID: Hashable {
        let table = StateTable()
        return (0..<2).map { _ in
            let frame = Frame(contentSize: Size<Pixels>(width: Pixels(100), height: Pixels(60)),
                              scaleFactor: 1, stateTable: table)
            var tree = ScrollView(.vertical) {
                if path == .uniform {
                    List(items, rowHeight: Pixels(20)) { _ in ConditionalCounter("x", ConditionalReads()) }
                } else {
                    List(items) { _ in ConditionalCounter("x", ConditionalReads()) }
                }
            }
            frame.render(&tree)
            return frame.listIdentityWork
        }
    }
    for path in [Path.uniform, .variable] {
        var windows: [Int] = []
        for n in counts {
            let ints = work((0..<n).map { IntItem(id: $0) }, path)
            let twins = work((0..<n).map { TwinItem(id: Twin(u: $0)) }, path)
            // The cold frame has no viewport yet, so it realises every row (`MP-I`); the warm
            // frame is the window.
            #expect(ints[0].rows == n && twins[0].rows == n, "\(path) \(n): cold \(ints[0]) \(twins[0])")
            #expect(ints.allSatisfy { $0.keyed == 0 }, "\(path) \(n) ints: \(ints)")
            #expect(twins.allSatisfy { $0.keyed == $0.rows }, "\(path) \(n) twins: \(twins)")
            #expect(twins[1].rows == ints[1].rows, "\(path) \(n): warm window \(ints[1]) \(twins[1])")
            print("LH-E work \(path) n=\(n): ints cold/warm \(ints[0])/\(ints[1]), twins cold/warm \(twins[0])/\(twins[1])")
            windows.append(ints[1].rows)
        }
        #expect(Set(windows).count == 1 && windows[0] > 0 && windows[0] < 100, "\(path): \(windows)")
    }
}
