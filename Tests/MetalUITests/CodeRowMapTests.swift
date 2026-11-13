import Testing
@testable import MetalUI

// `CodeRowMap` (`CV-S`) against an array model under seeded random builds and splices: display row to buffer
// row or virtual line, buffer row to display row, the counts, and the gap-keeping rules of an edit.

@MainActor private func group(_ id: Int, lines: Int) -> VirtualGroup {
    let line = VirtualLine(text: "g\(id)", bytes: Array("g\(id)".utf8), hash: UInt64(id), styling: CodeDecorations.LineStyling(), marker: nil)
    return VirtualGroup(lines: Array(repeating: line, count: lines), gutterBar: nil, background: nil)
}

private struct Lcg {
    var state: UInt64
    mutating func next(_ bound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(max(1, bound)))
    }
}

/// The model: gaps as (position, id, height) in order.
private struct Model {
    var rows: Int
    var gaps: [(position: Int, id: Int, height: Int)]

    /// The display sequence: `.buffer(row)` or `.virtual(id, line)`.
    var display: [(buffer: Int?, id: Int, line: Int)] {
        var out: [(buffer: Int?, id: Int, line: Int)] = []
        var gap = 0
        for row in 0...rows {
            while gap < gaps.count, gaps[gap].position == row {
                for l in 0..<gaps[gap].height { out.append((nil, gaps[gap].id, l)) }
                gap += 1
            }
            if row < rows { out.append((row, 0, 0)) }
        }
        return out
    }

    mutating func splice(at p: Int, removing n: Int, inserting m: Int) {
        var next: [(position: Int, id: Int, height: Int)] = []
        for gap in gaps {
            if gap.position <= p { next.append(gap) }
            else if gap.position < p + n { continue }
            else { next.append((gap.position - n + m, gap.id, gap.height)) }
        }
        gaps = next
        rows += m - n
    }
}

@MainActor @Test func theRowMapMatchesAnArrayModelUnderRandomBuildsAndSplices() {
    var rng = Lcg(state: 0xC0DE)
    for round in 0..<60 {
        let rows = 1 + rng.next(80)
        var positions: [Int] = []
        for _ in 0..<rng.next(25) { positions.append(rng.next(rows + 1)) }
        positions.sort()
        var model = Model(rows: rows, gaps: [])
        var entries: [(position: Int, group: VirtualGroup)] = []
        for (i, position) in positions.enumerated() {
            let height = 1 + rng.next(4)
            model.gaps.append((position, i + 1, height))
            entries.append((position, group(i + 1, lines: height)))
        }
        let map = CodeRowMap(rowCount: rows)
        map.build(rowCount: rows, groups: entries)
        func check(_ label: String) {
            let expected = model.display
            #expect(map.displayRowCount == expected.count && map.rowCount == model.rows, "round \(round) \(label): counts")
            for (index, want) in expected.enumerated() {
                switch map.row(atDisplay: index) {
                case .buffer(let row):
                    #expect(want.buffer == row, "round \(round) \(label): display \(index) is buffer \(row), model \(want)")
                    #expect(map.displayRow(ofBufferRow: row) == index, "round \(round) \(label): buffer \(row) at \(index)")
                case .virtual(let g, let line, let gap):
                    #expect(want.buffer == nil && want.line == line && g.lines[0].text == "g\(want.id)",
                            "round \(round) \(label): display \(index) is virtual \(g.lines[0].text)/\(line), model \(want)")
                    #expect(model.gaps.contains { $0.id == want.id && $0.position == gap }, "gap \(gap)")
                }
            }
        }
        check("built")
        for step in 0..<12 {
            let p = rng.next(model.rows + 1)
            let removed = rng.next(min(4, model.rows - p) + 1)
            let added = rng.next(4)
            map.splice(at: p, removing: removed, inserting: added)
            model.splice(at: p, removing: removed, inserting: added)
            check("splice \(step) at \(p) -\(removed) +\(added)")
        }
    }
}

/// A newline above many groups touches a logarithmic number of nodes (the model above proves the answer; this
/// the cost). **Mutation:** shifting by a walk over every node.
@MainActor @Test func aSpliceAboveTenThousandGroupsVisitsFewNodes() {
    let map = CodeRowMap(rowCount: 30_000)
    map.build(rowCount: 30_000, groups: (0..<10_000).map { (20 + 2 * $0, group($0 + 1, lines: 1)) })
    let before = RunTreeStats.nodesVisited
    map.splice(at: 6, removing: 0, inserting: 1)
    let visited = RunTreeStats.nodesVisited - before
    #expect(visited < 200, "nodes visited \(visited)")
    // The first gap was at row 20; after the newline it is at 21, so buffer row 20 still has no virtual line before it.
    #expect(map.displayRow(ofBufferRow: 20) == 20 && map.displayRow(ofBufferRow: 21) == 22, "\(map.displayRow(ofBufferRow: 21))")
}

/// Owners (`CV-AO`): every group keeps the owner and priority it was built with, and `allGroups()` lists the groups
/// with their gap positions in order, against the array model, after seeded random builds and splices. This is what
/// the owner merge reads (another owner's groups off the live map), so a wrong position or order after an edit would
/// put a diagnostic's note on the wrong line. **Mutation:** `allGroups()` reporting the node's own extent instead of
/// the running position.
@MainActor @Test func theGroupsOfSeveralOwnersListInOrderWithTheirPositionsUnderRandomSplices() {
    var rng = Lcg(state: 0x0A11)
    for round in 0..<40 {
        let rows = 1 + rng.next(80)
        var positions: [Int] = []
        for _ in 0..<(1 + rng.next(25)) { positions.append(rng.next(rows + 1)) }
        positions.sort()
        var model = Model(rows: rows, gaps: [])
        var owners: [Int: UInt16] = [:]
        var entries: [(position: Int, group: VirtualGroup)] = []
        for (i, position) in positions.enumerated() {
            let height = 1 + rng.next(3)
            let owner = UInt16(rng.next(3))
            let line = VirtualLine(text: "g\(i + 1)", bytes: Array("g\(i + 1)".utf8), hash: UInt64(i + 1), styling: CodeDecorations.LineStyling(), marker: nil)
            model.gaps.append((position, i + 1, height))
            owners[i + 1] = owner
            entries.append((position, VirtualGroup(lines: Array(repeating: line, count: height), gutterBar: nil, background: nil,
                                                   owner: owner, priority: Int(owner) * 3)))
        }
        let map = CodeRowMap(rowCount: rows)
        map.build(rowCount: rows, groups: entries)
        func check(_ label: String) {
            let listed = map.allGroups()
            #expect(listed.count == model.gaps.count, "round \(round) \(label): \(listed.count) groups, model \(model.gaps.count)")
            for (got, want) in zip(listed, model.gaps) {
                #expect(got.position == want.position && got.group.lines[0].text == "g\(want.id)"
                        && got.group.owner == owners[want.id] && got.group.priority == Int(owners[want.id]!) * 3,
                        "round \(round) \(label): \(got.position) \(got.group.lines[0].text) vs \(want)")
            }
        }
        check("built")
        for step in 0..<10 {
            let p = rng.next(model.rows + 1)
            let removed = rng.next(min(4, model.rows - p) + 1)
            let added = rng.next(4)
            map.splice(at: p, removing: removed, inserting: added)
            model.splice(at: p, removing: removed, inserting: added)
            check("splice \(step)")
        }
    }
}
